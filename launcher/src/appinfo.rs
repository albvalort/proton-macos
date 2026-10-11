//! Reader for the Steam client's `appcache/appinfo.vdf` (format v29), which caches the product
//! info of every app the client knows about: name, type, oslist, depots and launch entries.

use crate::kv::{Keys, Reader, Value};
use anyhow::{bail, Context, Result};
use std::collections::HashMap;
use std::path::Path;

const MAGIC_V29: u32 = 0x0756_4429;

pub struct AppInfo {
    pub appid: u32,
    pub data: Value,
}

impl AppInfo {
    pub fn name(&self) -> &str {
        self.data
            .path("appinfo/common/name")
            .and_then(Value::as_str)
            .unwrap_or("?")
    }

    pub fn app_type(&self) -> &str {
        self.data
            .path("appinfo/common/type")
            .and_then(Value::as_str)
            .unwrap_or("")
    }

    pub fn oslist(&self) -> &str {
        self.data
            .path("appinfo/common/oslist")
            .and_then(Value::as_str)
            .unwrap_or("")
    }

    pub fn install_dir(&self) -> Option<&str> {
        self.data
            .path("appinfo/config/installdir")
            .and_then(Value::as_str)
    }

    /// Launch entries usable on Windows (no oslist, or one containing "windows"), in order.
    pub fn windows_launches(&self) -> Vec<Launch> {
        let Some(launch) = self.data.path("appinfo/config/launch") else {
            return Vec::new();
        };
        launch
            .entries()
            .iter()
            .filter_map(|(_, entry)| {
                let executable = entry.get("executable")?.as_str()?.to_string();
                let oslist = entry
                    .path("config/oslist")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                if !oslist.is_empty() && !oslist.contains("windows") {
                    return None;
                }
                let launch_type = entry
                    .get("type")
                    .and_then(Value::as_str)
                    .unwrap_or("default");
                if !(launch_type == "default" || launch_type == "none") {
                    return None;
                }
                Some(Launch {
                    executable,
                    arguments: entry
                        .get("arguments")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                    workingdir: entry
                        .get("workingdir")
                        .and_then(Value::as_str)
                        .map(str::to_string),
                    description: entry
                        .get("description")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_string(),
                })
            })
            .collect()
    }
}

#[derive(Debug, Clone)]
pub struct Launch {
    pub executable: String,
    pub arguments: String,
    pub workingdir: Option<String>,
    pub description: String,
}

/// Parses appinfo.vdf, keeping only the apps accepted by `keep` (by appid) to save memory.
pub fn read(path: &Path, keep: impl Fn(u32) -> bool) -> Result<HashMap<u32, AppInfo>> {
    let data = std::fs::read(path).with_context(|| format!("reading {}", path.display()))?;
    let mut r = Reader::new(&data);
    let magic = r.u32()?;
    if magic != MAGIC_V29 {
        bail!("unsupported appinfo.vdf format {magic:#x} (expected v29 {MAGIC_V29:#x})");
    }
    let _universe = r.u32()?;
    let table_offset = r.u64()? as usize;

    let strings = {
        let mut t = Reader::new(&data);
        t.pos = table_offset;
        let count = t.u32()? as usize;
        (0..count).map(|_| t.cstr()).collect::<Result<Vec<_>>>()?
    };
    let keys = Keys::Table(&strings);

    let mut apps = HashMap::new();
    loop {
        let appid = r.u32()?;
        if appid == 0 {
            break;
        }
        let size = r.u32()? as usize;
        let entry_start = r.pos;
        if keep(appid) {
            // infostate, last updated, pics token, sha1, change number, binary sha1
            r.take(4 + 4 + 8 + 20 + 4 + 20)?;
            let data = r
                .map(&keys)
                .with_context(|| format!("parsing appinfo for app {appid}"))?;
            apps.insert(appid, AppInfo { appid, data });
        }
        r.pos = entry_start + size;
    }
    Ok(apps)
}
