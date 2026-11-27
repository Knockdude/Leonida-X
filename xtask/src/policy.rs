//! Rule #1, statically: the repository only ever contains small text files
//! that we wrote. See docs/asset-policy.md.
//!
//! This is an allowlist, not a blocklist: a file passes only if its name is
//! on the list, it is not too big, it is text, and it does not smuggle data
//! inside text (long hex/base64 runs). A symbolic link carries no data of
//! its own: it passes when it points inside the repository.

use std::collections::HashSet;
use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result, bail};

const MAX_FILE_SIZE: usize = 512 * 1024;
const MAX_ENCODED_RUN: usize = 512;

const ALLOWED_EXTENSIONS: &[&str] = &[
    "rs", "toml", "md", "txt", "lock", "yml", "yaml", "json", "hlsl", "hlsli", "ps1", "cmd", "sh",
];
const ALLOWED_NAMES: &[&str] = &[
    ".gitignore",
    ".gitattributes",
    ".editorconfig",
    ".leonida-root",
    "pre-commit",
    "LICENSE",
    "LICENSE-MIT",
    "LICENSE-APACHE",
];

/// Paths explicitly exempted, with a reason. Keep this empty if at all possible.
const EXCEPTIONS: &[(&str, &str)] = &[(
    "crates/leonida-formats/src/bcpack-tables.bin",
    "the BCPack format's constant tables: nothing decodes without them and they cannot be derived (owner's decision, 2026-11-23; docs/asset-policy.md)",
)];

/// Signatures of formats that must never be committed.
const FORBIDDEN_MAGIC: &[(&[u8], &str)] = &[
    (b"MZ", "PE executable"),
    (b"DXBC", "shader container"),
    (b"DDS ", "DDS texture"),
    (b"RIFF", "RIFF (audio/video)"),
    (b"BC\xC0\xDE", "LLVM bitcode"),
    (b"Microsoft C/C++ MSF", "PDB"),
    (b"!<arch>", "library archive"),
    (b"PK\x03\x04", "zip"),
    (b"7z\xBC\xAF", "7-zip"),
    (b"MSCF", "cabinet"),
    (b"\xD0\xCF\x11\xE0", "MSI/OLE"),
];

pub fn run(root: &Path, staged: bool) -> Result<()> {
    let files = list_files(root, staged)?;
    let links = symlinks(root)?;
    let mut violations = Vec::new();
    for path in &files {
        if EXCEPTIONS.iter().any(|(p, _)| p == path) {
            continue;
        }
        let link = links.contains(path);
        // A link's blob in the index is its target, whether or not this
        // clone made a real link of it.
        let content = if staged || link {
            let out = Command::new("git")
                .args(["show", &format!(":{path}")])
                .current_dir(root)
                .output()?;
            if !out.status.success() {
                continue; // deleted in the index
            }
            out.stdout
        } else {
            match std::fs::read(root.join(path)) {
                Ok(c) => c,
                Err(_) => continue,
            }
        };
        let problems = if link {
            check_link(path, &content)
        } else {
            check(path, &content)
        };
        for problem in problems {
            violations.push(format!("{path}: {problem}"));
        }
    }
    if violations.is_empty() {
        println!("asset policy: {} files ok", files.len());
        return Ok(());
    }
    for v in &violations {
        eprintln!("POLICY: {v}");
    }
    bail!(
        "{} asset-policy violation(s). Nothing from the game may be committed; \
         see docs/asset-policy.md",
        violations.len()
    )
}

fn list_files(root: &Path, staged: bool) -> Result<Vec<String>> {
    let git = |args: &[&str]| -> Result<Option<Vec<String>>> {
        let out = match Command::new("git")
            .args(args)
            .current_dir(root)
            .output()
        {
            Ok(out) => out,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error).context("running git"),
        };
        if !out.status.success() {
            return Ok(None);
        }
        Ok(Some(
            out.stdout
                .split(|&b| b == 0)
                .filter(|s| !s.is_empty())
                .map(|s| String::from_utf8_lossy(s).replace('\\', "/"))
                .collect(),
        ))
    };
    if staged {
        return git(&[
            "diff",
            "--cached",
            "--name-only",
            "--diff-filter=ACMR",
            "-z",
        ])?
        .context("--staged needs a git repository");
    }
    if let Some(mut tracked) = git(&[
        "ls-files",
        "-z",
        "--cached",
        "--others",
        "--exclude-standard",
    ])? {
        tracked.sort();
        tracked.dedup();
        return Ok(tracked);
    }
    // Not a git repository: walk everything except build output.
    Ok(walkdir::WalkDir::new(root)
        .into_iter()
        .filter_entry(|e| !matches!(e.file_name().to_str(), Some("target" | ".git")))
        .filter_map(Result::ok)
        .filter(|e| e.file_type().is_file())
        .filter_map(|e| {
            e.path()
                .strip_prefix(root)
                .ok()
                .map(|p| p.to_string_lossy().replace('\\', "/"))
        })
        .collect())
}

/// The paths the index holds as symbolic links (mode 120000).
fn symlinks(root: &Path) -> Result<HashSet<String>> {
    let out = match Command::new("git")
        .args(["ls-files", "-s", "-z"])
        .current_dir(root)
        .output()
    {
        Ok(out) => out,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(HashSet::new()),
        Err(error) => return Err(error).context("running git"),
    };
    if !out.status.success() {
        return Ok(HashSet::new());
    }
    Ok(out
        .stdout
        .split(|&b| b == 0)
        .filter_map(|entry| {
            let entry = String::from_utf8_lossy(entry);
            let (meta, path) = entry.split_once('\t')?;
            meta.starts_with("120000 ").then(|| path.replace('\\', "/"))
        })
        .collect())
}

/// All problems with a symbolic link at `path` whose target is `target`.
/// Only a relative path to a place inside the repository passes; what it
/// points at is checked as a file of its own. Pure, for testing.
pub fn check_link(path: &str, target: &[u8]) -> Vec<String> {
    let Ok(target) = std::str::from_utf8(target) else {
        return vec!["symbolic link target is not text".to_owned()];
    };
    if target.is_empty() || target.len() > 1024 || target.chars().any(char::is_control) {
        return vec!["symbolic link target is not a plain path".to_owned()];
    }
    if target.starts_with(['/', '\\']) || target.contains(':') {
        return vec![format!("symbolic link to an absolute path ({target})")];
    }
    let mut place: Vec<&str> = path.split('/').collect();
    place.pop(); // the link's own name
    for part in target.split(['/', '\\']) {
        match part {
            "" | "." => {}
            ".." => {
                if place.pop().is_none() {
                    return vec![format!("symbolic link leaves the repository ({target})")];
                }
            }
            name => place.push(name),
        }
    }
    if place.is_empty() {
        return vec![format!("symbolic link to the repository root ({target})")];
    }
    Vec::new()
}

/// All problems with one file. Pure, for testing.
pub fn check(path: &str, content: &[u8]) -> Vec<String> {
    let mut problems = Vec::new();
    let name = path.rsplit('/').next().unwrap_or(path);
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase());
    let allowed = ALLOWED_NAMES.contains(&name)
        || ext
            .as_deref()
            .is_some_and(|e| ALLOWED_EXTENSIONS.contains(&e));
    if !allowed {
        problems.push("file type not on the allowlist".to_owned());
    }
    if content.len() > MAX_FILE_SIZE {
        problems.push(format!(
            "{} bytes exceeds the {MAX_FILE_SIZE}-byte limit",
            content.len()
        ));
    }
    for (magic, what) in FORBIDDEN_MAGIC {
        if content.starts_with(magic) {
            problems.push(format!("looks like a {what}"));
        }
    }
    if content.contains(&0) {
        problems.push("binary content (NUL bytes)".to_owned());
    } else if let Some(run) = longest_encoded_run(content)
        && run > MAX_ENCODED_RUN
    {
        problems.push(format!("{run}-character hex/base64 run (embedded data?)"));
    }
    problems
}

/// Longest run of characters that could be hex or base64 payload.
fn longest_encoded_run(content: &[u8]) -> Option<usize> {
    let is_payload = |b: &u8| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'=');
    content.split(|b| !is_payload(b)).map(<[u8]>::len).max()
}

#[cfg(test)]
mod tests {
    use super::{check, check_link};

    /// Enforces the policy wherever tests run, even in clones without the hook.
    #[test]
    fn repository_passes_policy() {
        super::run(&crate::workspace_root(), false).unwrap();
    }

    #[test]
    fn accepts_source() {
        assert!(check("crates/x/src/lib.rs", b"fn main() {}\n").is_empty());
        assert!(check(".gitignore", b"/target/\n").is_empty());
        assert!(check(".githooks/pre-commit", b"#!/bin/sh\n").is_empty());
    }

    #[test]
    fn rejects_game_like_files() {
        assert!(!check("assets/tex.dds", b"DDS \x7c\0\0\0").is_empty());
        assert!(
            !check("notes.txt", b"MZ\x90\0").is_empty(),
            "magic wins over extension"
        );
        assert!(
            !check("data.bin", b"hello").is_empty(),
            "extension not allowed"
        );
        assert!(
            !check("a.rs", &vec![b'a'; 600 * 1024]).is_empty(),
            "too big"
        );
    }

    #[test]
    fn accepts_links_inside_the_repository() {
        assert!(check_link(".agents/skills", b"../.claude/skills").is_empty());
        assert!(check_link("a/b/link.md", b"../c/./d.md").is_empty());
    }

    #[test]
    fn rejects_links_that_leave_the_repository() {
        assert!(!check_link(".agents/skills", b"../../outside").is_empty());
        assert!(!check_link("link", b"/etc/passwd").is_empty());
        assert!(!check_link("link", b"C:\\Windows").is_empty());
        assert!(!check_link("link", b".").is_empty(), "the root itself");
        assert!(!check_link("link", b"a\0b").is_empty());
    }

    #[test]
    fn rejects_data_smuggled_into_text() {
        let blob = format!("const DATA: &str = \"{}\";", "A1".repeat(400));
        assert!(!check("src/blob.rs", blob.as_bytes()).is_empty());
    }
}
