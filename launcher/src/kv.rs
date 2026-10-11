//! Valve binary KeyValues, as used by `appinfo.vdf` and `shortcuts.vdf`.
//!
//! Each entry is a type byte, a key and a value. Keys are NUL-terminated strings, except in
//! `appinfo.vdf` v29+ where they are 32-bit indexes into a string table at the end of the file.

use anyhow::{bail, Context, Result};

const TYPE_MAP: u8 = 0x00;
const TYPE_STRING: u8 = 0x01;
const TYPE_INT32: u8 = 0x02;
const TYPE_FLOAT: u8 = 0x03;
const TYPE_UINT64: u8 = 0x07;
const TYPE_END: u8 = 0x08;
const TYPE_INT64: u8 = 0x0a;
const TYPE_END_ALT: u8 = 0x0b;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Map(Vec<(String, Value)>),
    Str(String),
    Int(i32),
    Float(f32),
    U64(u64),
    I64(i64),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Map(entries) => entries
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case(key))
                .map(|(_, v)| v),
            _ => None,
        }
    }

    /// Follows a `/`-separated path of keys.
    pub fn path(&self, path: &str) -> Option<&Value> {
        path.split('/').try_fold(self, |v, key| v.get(key))
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn entries(&self) -> &[(String, Value)] {
        match self {
            Value::Map(entries) => entries,
            _ => &[],
        }
    }
}

/// How keys are encoded.
pub enum Keys<'a> {
    /// NUL-terminated strings.
    Inline,
    /// u32 index into this table (appinfo.vdf v29+).
    Table(&'a [String]),
}

pub struct Reader<'a> {
    data: &'a [u8],
    pub pos: usize,
}

impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Reader { data, pos: 0 }
    }

    pub fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self
            .pos
            .checked_add(n)
            .filter(|&e| e <= self.data.len())
            .context("unexpected end of data")?;
        let slice = &self.data[self.pos..end];
        self.pos = end;
        Ok(slice)
    }

    pub fn u8(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }

    pub fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }

    pub fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }

    pub fn cstr(&mut self) -> Result<String> {
        let rest = &self.data[self.pos..];
        let len = rest
            .iter()
            .position(|&b| b == 0)
            .context("unterminated string")?;
        let s = String::from_utf8_lossy(&rest[..len]).into_owned();
        self.pos += len + 1;
        Ok(s)
    }

    fn key(&mut self, keys: &Keys) -> Result<String> {
        match keys {
            Keys::Inline => self.cstr(),
            Keys::Table(table) => {
                let idx = self.u32()? as usize;
                table
                    .get(idx)
                    .cloned()
                    .with_context(|| format!("string index {idx} out of range"))
            }
        }
    }

    /// Reads entries until the end marker of the current map.
    pub fn map(&mut self, keys: &Keys) -> Result<Value> {
        let mut entries = Vec::new();
        loop {
            let ty = self.u8()?;
            if ty == TYPE_END || ty == TYPE_END_ALT {
                return Ok(Value::Map(entries));
            }
            let key = self.key(keys)?;
            let value = match ty {
                TYPE_MAP => self.map(keys)?,
                TYPE_STRING => Value::Str(self.cstr()?),
                TYPE_INT32 => Value::Int(self.u32()? as i32),
                TYPE_FLOAT => Value::Float(f32::from_le_bytes(self.take(4)?.try_into().unwrap())),
                TYPE_UINT64 => Value::U64(self.u64()?),
                TYPE_INT64 => Value::I64(self.u64()? as i64),
                other => bail!(
                    "unknown KeyValues type {other:#x} at offset {}",
                    self.pos - 1
                ),
            };
            entries.push((key, value));
        }
    }
}

/// Serializes a map with inline keys (shortcuts.vdf style), including its end marker.
pub fn write_map(out: &mut Vec<u8>, entries: &[(String, Value)]) {
    for (key, value) in entries {
        let ty = match value {
            Value::Map(_) => TYPE_MAP,
            Value::Str(_) => TYPE_STRING,
            Value::Int(_) => TYPE_INT32,
            Value::Float(_) => TYPE_FLOAT,
            Value::U64(_) => TYPE_UINT64,
            Value::I64(_) => TYPE_INT64,
        };
        out.push(ty);
        out.extend_from_slice(key.as_bytes());
        out.push(0);
        match value {
            Value::Map(inner) => write_map(out, inner),
            Value::Str(s) => {
                out.extend_from_slice(s.as_bytes());
                out.push(0);
            }
            Value::Int(i) => out.extend_from_slice(&i.to_le_bytes()),
            Value::Float(f) => out.extend_from_slice(&f.to_le_bytes()),
            Value::U64(u) => out.extend_from_slice(&u.to_le_bytes()),
            Value::I64(i) => out.extend_from_slice(&i.to_le_bytes()),
        }
    }
    out.push(TYPE_END);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_inline_keys() {
        let doc = vec![(
            "shortcuts".to_string(),
            Value::Map(vec![(
                "0".to_string(),
                Value::Map(vec![
                    ("appid".to_string(), Value::Int(-1234)),
                    ("AppName".to_string(), Value::Str("Downwell".into())),
                    ("tags".to_string(), Value::Map(vec![])),
                ]),
            )]),
        )];
        let mut out = Vec::new();
        write_map(&mut out, &doc);
        let parsed = Reader::new(&out).map(&Keys::Inline).unwrap();
        assert_eq!(parsed, Value::Map(doc));
        assert_eq!(
            parsed.path("shortcuts/0/appname").and_then(Value::as_str),
            Some("Downwell")
        );
    }
}
