//! Non-Steam shortcuts in `userdata/<account>/config/shortcuts.vdf` (binary KeyValues), so a
//! Windows game launched through pmac shows up and starts from the Steam library.
//!
//! Steam rewrites this file on exit, so it must not be running while we write.

use crate::kv::{self, Keys, Reader, Value};
use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};

pub struct Shortcut {
    pub name: String,
    pub exe: PathBuf,
    pub start_dir: PathBuf,
    pub launch_options: String,
    pub icon: Option<PathBuf>,
}

impl Shortcut {
    /// The id Steam derives for a shortcut (also used to name its artwork files).
    pub fn appid(&self) -> u32 {
        let exe = quoted(&self.exe);
        let mut h = crc32fast::Hasher::new();
        h.update(exe.as_bytes());
        h.update(self.name.as_bytes());
        h.finalize() | 0x8000_0000
    }

    fn to_kv(&self) -> Value {
        let s = |v: &str| Value::Str(v.to_string());
        Value::Map(vec![
            ("appid".into(), Value::Int(self.appid() as i32)),
            ("AppName".into(), s(&self.name)),
            ("Exe".into(), s(&quoted(&self.exe))),
            ("StartDir".into(), s(&quoted(&self.start_dir))),
            (
                "icon".into(),
                s(&self
                    .icon
                    .as_deref()
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_default()),
            ),
            ("ShortcutPath".into(), s("")),
            ("LaunchOptions".into(), s(&self.launch_options)),
            ("IsHidden".into(), Value::Int(0)),
            ("AllowDesktopConfig".into(), Value::Int(1)),
            ("AllowOverlay".into(), Value::Int(1)),
            ("OpenVR".into(), Value::Int(0)),
            ("Devkit".into(), Value::Int(0)),
            ("DevkitGameID".into(), s("")),
            ("DevkitOverrideAppID".into(), Value::Int(0)),
            ("LastPlayTime".into(), Value::Int(0)),
            ("FlatpakAppID".into(), s("")),
            ("tags".into(), Value::Map(vec![])),
        ])
    }
}

fn quoted(p: &Path) -> String {
    format!("\"{}\"", p.display())
}

/// Adds or replaces (same AppName) a shortcut. Returns the shortcut's appid.
pub fn upsert(path: &Path, shortcut: &Shortcut) -> Result<u32> {
    let mut list: Vec<Value> = if path.exists() {
        let data = std::fs::read(path)?;
        let doc = Reader::new(&data)
            .map(&Keys::Inline)
            .with_context(|| format!("parsing {}", path.display()))?;
        match doc.get("shortcuts") {
            Some(Value::Map(entries)) => entries.iter().map(|(_, v)| v.clone()).collect(),
            Some(_) => bail!("unexpected shortcuts.vdf layout"),
            None => Vec::new(),
        }
    } else {
        Vec::new()
    };
    list.retain(|e| e.get("AppName").and_then(Value::as_str) != Some(shortcut.name.as_str()));
    list.push(shortcut.to_kv());

    let entries = list
        .into_iter()
        .enumerate()
        .map(|(i, v)| (i.to_string(), v))
        .collect();
    let mut out = Vec::new();
    kv::write_map(&mut out, &[("shortcuts".to_string(), Value::Map(entries))]);
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    if path.exists() {
        std::fs::copy(path, path.with_extension("vdf.pmac-backup"))?;
    }
    std::fs::write(path, out)?;
    Ok(shortcut.appid())
}

/// Copies the official artwork Steam cached for `appid` into the shortcut's grid slots.
pub fn copy_library_art(art_dir: &Path, grid_dir: &Path, shortcut_id: u32) -> Result<usize> {
    std::fs::create_dir_all(grid_dir)?;
    // (source names in librarycache, target suffix in config/grid)
    let slots: [(&[&str], &str); 4] = [
        (&["library_600x900.jpg"], "p"),
        (&["library_hero.jpg"], "_hero"),
        (&["logo.png"], "_logo"),
        (&["header.jpg", "library_header.jpg"], ""),
    ];
    let mut copied = 0;
    for (sources, suffix) in slots {
        if let Some(src) = sources.iter().map(|s| art_dir.join(s)).find(|p| p.exists()) {
            let ext = src.extension().and_then(|e| e.to_str()).unwrap_or("jpg");
            std::fs::copy(&src, grid_dir.join(format!("{shortcut_id}{suffix}.{ext}")))?;
            copied += 1;
        }
    }
    Ok(copied)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upsert_creates_and_replaces() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("shortcuts.vdf");
        let mut sc = Shortcut {
            name: "Downwell".into(),
            exe: "/usr/local/bin/pmac".into(),
            start_dir: "/tmp".into(),
            launch_options: "run 360740".into(),
            icon: None,
        };
        upsert(&path, &sc).unwrap();
        sc.launch_options = "run 360740 --launch 0".into();
        let id = upsert(&path, &sc).unwrap();

        let data = std::fs::read(&path).unwrap();
        let doc = Reader::new(&data).map(&Keys::Inline).unwrap();
        let entries = doc.get("shortcuts").unwrap().entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(
            entries[0].1.get("LaunchOptions").and_then(Value::as_str),
            Some("run 360740 --launch 0")
        );
        assert_eq!(entries[0].1.get("appid"), Some(&Value::Int(id as i32)));
        assert!(id & 0x8000_0000 != 0);
    }
}
