//! pmac — Proton-macOS launcher.
//!
//! Lists the Steam library, downloads Windows depots, runs games through Proton-macOS with the
//! environment Steam would provide, and adds them to the Steam library as shortcuts.

mod appinfo;
mod compat;
mod depots;
mod kv;
mod run;
mod shortcuts;
mod steam;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "pmac",
    version,
    about = "Run Windows Steam games on macOS with Proton-macOS"
)]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Log in for downloads with a QR code (scan it with the Steam mobile app). No password is asked.
    Login {
        /// Account name (default: the most recent Steam account on this Mac)
        #[arg(long)]
        username: Option<String>,
    },
    /// List games in the Steam library
    List {
        /// Include games with a native macOS version
        #[arg(long)]
        all: bool,
        #[arg(long)]
        json: bool,
    },
    /// Download the Windows version of a game into the Proton-macOS library
    Install {
        appid: u32,
        #[arg(long)]
        username: Option<String>,
        /// Verify files that are already present
        #[arg(long)]
        validate: bool,
    },
    /// Run an installed game through Proton-macOS
    Run {
        appid: u32,
        /// Launch entry to use (see `pmac info`)
        #[arg(long, default_value_t = 0)]
        launch: usize,
        /// Extra arguments for the game
        #[arg(last = true)]
        args: Vec<String>,
    },
    /// Show what pmac knows about a game
    Info { appid: u32 },
    /// Add a game to the Steam library as a shortcut that runs it through pmac (Steam must be closed)
    Shortcut {
        appid: u32,
        /// Write even if Steam is running (Steam may overwrite it on exit)
        #[arg(long)]
        force: bool,
    },
}

fn load_app(appid: u32) -> Result<appinfo::AppInfo> {
    let mut apps = appinfo::read(&steam::appinfo_path(), |id| id == appid)?;
    apps.remove(&appid).with_context(|| {
        format!("app {appid} is not in Steam's app cache (is it in your library?)")
    })
}

fn username(arg: Option<String>) -> Result<String> {
    match arg {
        Some(u) => Ok(u),
        None => Ok(steam::current_user()?.0),
    }
}

fn main() -> Result<()> {
    match Cli::parse().command {
        Cmd::Login { username: user } => {
            let user = username(user)?;
            eprintln!("pmac: logging in as {user}: scan the QR code with the Steam mobile app");
            depots::login(&user)?;
            eprintln!("pmac: logged in; DepotDownloader keeps the session token");
        }
        Cmd::List { all, json } => {
            let library: std::collections::HashSet<u32> =
                steam::library_appids()?.into_iter().collect();
            let apps = appinfo::read(&steam::appinfo_path(), |id| library.contains(&id))?;
            let mut games: Vec<_> = apps
                .values()
                .filter(|a| a.app_type().eq_ignore_ascii_case("game"))
                .filter(|a| all || !a.oslist().contains("macos"))
                .collect();
            games.sort_by_key(|a| a.name().to_lowercase());
            if json {
                let rows: Vec<_> = games
                    .iter()
                    .map(|a| {
                        serde_json::json!({"appid": a.appid, "name": a.name(), "oslist": a.oslist(),
                                                "installed": run::find_install_dir(a).is_some()})
                    })
                    .collect();
                println!("{}", serde_json::to_string_pretty(&rows)?);
            } else {
                for a in &games {
                    let installed = if run::find_install_dir(a).is_some() {
                        "installed"
                    } else {
                        ""
                    };
                    let status = compat::load(a.appid)?
                        .and_then(|c| c.status)
                        .unwrap_or_default();
                    println!(
                        "{:>8}  {:<50} {:<18} {:<9} {}",
                        a.appid,
                        a.name(),
                        a.oslist(),
                        installed,
                        status
                    );
                }
                eprintln!(
                    "{} games{}",
                    games.len(),
                    if all {
                        ""
                    } else {
                        " without a macOS version (use --all)"
                    }
                );
            }
        }
        Cmd::Install {
            appid,
            username: user,
            validate,
        } => {
            let info = load_app(appid)?;
            let installdir = info.install_dir().context("app has no installdir")?;
            let dir = steam::library_dir().join(installdir);
            eprintln!(
                "pmac: installing {} (Windows) into {}",
                info.name(),
                dir.display()
            );
            depots::install(appid, &username(user)?, &dir, validate)?;
            eprintln!("pmac: installed; run it with `pmac run {appid}`");
        }
        Cmd::Run {
            appid,
            launch,
            args,
        } => {
            let info = load_app(appid)?;
            let dir = run::find_install_dir(&info).with_context(|| {
                format!("{} is not installed (pmac install {appid})", info.name())
            })?;
            let plan = run::plan(&info, &dir, launch)?;
            let compat = compat::load(appid)?;
            std::process::exit(run::run(&info, &dir, &plan, compat.as_ref(), &args)?);
        }
        Cmd::Info { appid } => {
            let info = load_app(appid)?;
            println!(
                "{} ({appid})\n  type: {}\n  oslist: {}",
                info.name(),
                info.app_type(),
                info.oslist()
            );
            println!("  installdir: {}", info.install_dir().unwrap_or("-"));
            match run::find_install_dir(&info) {
                Some(d) => println!("  installed at: {}", d.display()),
                None => println!("  installed at: (not installed)"),
            }
            for (i, l) in info.windows_launches().iter().enumerate() {
                println!(
                    "  launch #{i}: {} {} {}",
                    l.executable, l.arguments, l.description
                );
            }
            match compat::load(appid)? {
                Some(c) => println!(
                    "  compat: {}",
                    serde_yaml::to_string(&c)?
                        .trim_end()
                        .replace('\n', "\n          ")
                ),
                None => println!("  compat: (no entry)"),
            }
        }
        Cmd::Shortcut { appid, force } => {
            if steam::is_steam_running() && !force {
                bail!("Steam is running: quit it first (it rewrites shortcuts.vdf on exit), or use --force");
            }
            let info = load_app(appid)?;
            let (_, steamid) = steam::current_user()?;
            let config = steam::userdata_config(steamid);
            let pmac = std::env::current_exe()?;
            let sc = shortcuts::Shortcut {
                name: info.name().to_string(),
                start_dir: pmac.parent().map(PathBuf::from).unwrap_or_default(),
                exe: pmac,
                launch_options: format!("run {appid}"),
                icon: Some(steam::library_art_dir(appid).join("logo.png")).filter(|p| p.exists()),
            };
            let id = shortcuts::upsert(&config.join("shortcuts.vdf"), &sc)?;
            let art = shortcuts::copy_library_art(
                &steam::library_art_dir(appid),
                &config.join("grid"),
                id,
            )?;
            println!(
                "added \"{}\" to the Steam library (shortcut id {id}, {art} artwork files)",
                info.name()
            );
        }
    }
    Ok(())
}
