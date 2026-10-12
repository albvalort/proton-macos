//! Per-game compatibility settings: `compat/<appid>.yaml`.
//!
//! ```yaml
//! name: ANIMAL WELL
//! status: playable          # playable | runs | menu | broken | untested
//! backend: d3dmetal         # dxvk | d3dmetal | wined3d  (PROTON_MAC_GFX)
//! env:                      # extra environment for proton
//!   PROTON_NO_MSYNC: "1"
//! notes: Menu and gameplay at 60 fps on M2.
//! ```

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct Compat {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub backend: Option<String>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default)]
    pub notes: Option<String>,
}

/// Directories searched for compat files, most specific first.
fn search_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(d) = std::env::var_os("PMAC_COMPAT_DIR") {
        dirs.push(PathBuf::from(d));
    }
    dirs.push(crate::steam::data_dir().join("compat"));
    // Resolve symlinks: install.sh links ~/.local/bin/pmac to the tool.
    if let Ok(exe) = std::env::current_exe().and_then(|p| p.canonicalize()) {
        // Installed tool: <tool>/bin/pmac -> <tool>/compat
        if let Some(tool) = exe.ancestors().nth(2) {
            dirs.push(tool.join("compat"));
        }
        // Development tree: <repo>/launcher/target/<profile>/pmac -> <repo>/compat
        if let Some(repo) = exe.ancestors().nth(4) {
            dirs.push(repo.join("compat"));
        }
    }
    dirs
}

pub fn load(appid: u32) -> Result<Option<Compat>> {
    for dir in search_dirs() {
        let path = dir.join(format!("{appid}.yaml"));
        if path.exists() {
            let text = std::fs::read_to_string(&path)?;
            let compat = serde_yaml::from_str(&text)
                .with_context(|| format!("parsing {}", path.display()))?;
            return Ok(Some(compat));
        }
    }
    Ok(None)
}
