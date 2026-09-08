# `index.pb` — recovered schema

There is no published `.proto` for the protobuf repository index, so this schema
was recovered by walking the wire format of a real payload, per
`INSTRUCTIONS.md` §6.2. Nothing here is guessed: every field below was observed
in a payload committed as a test fixture.

**Source of evidence**

| | |
|---|---|
| Payload | `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb` |
| Fetched | 2026-09-08 |
| Wire size | 105,452 bytes, gzip |
| Inflated | 698,014 bytes |
| Entries | 1,396 extensions, 2,212 sources |
| Fixture | `test/extensions/fixtures/keiyoushi_index.pb.gz` |

This is a **manga** repository. It is a format reference only — none of its
extensions can run in Mimasu. An anime-side payload is still needed to confirm
the two open items at the bottom.

## Two findings that changed the plan

**1. The payload is gzip, not bare protobuf.** It begins `1f 8b 08`. §6.2
originally described decoding it directly; it must be inflated first. The
parser sniffs the magic bytes and inflates transparently.

**2. `index.min.json` is no longer the same catalogue.** §6.2 proposed deriving
the schema by diffing the two formats from the same repository. That does not
work here: this repository has migrated to protobuf and left the JSON index as
a **765-byte stub containing two placeholder entries** named "Outdated App" and
"Update to Mihon 0.20.1+", whose only purpose is to tell old clients to
upgrade.

So the JSON index cannot be treated as a fallback carrying the same data. A
client that reads only `index.min.json` sees two fake extensions and no
catalogue. Both formats must be supported, and the protobuf one must be
preferred where a repository offers both.

The diff did still confirm the JSON field names in §6.1, which had been marked
VERIFY: `name`, `pkg`, `apk`, `lang`, `code`, `version`, `nsfw`, and
`sources[].{name, lang, id, baseUrl}`.

## Schema

Field numbers are what matter; names below are ours.

```proto
// Top level
message RepoIndex {
  string name              = 1;    // "Keiyoushi"
  string short_name        = 2;    // "KEI"
  string signing_key_sha256 = 3;   // 64 lowercase hex chars
  RepoLinks links          = 4;
  Catalog catalog          = 101;  // note the gap
}

message RepoLinks {
  string website = 1;              // "https://keiyoushi.github.io"
  string social  = 2;              // "https://discord.gg/..."
}

message Catalog {
  repeated Extension extensions = 1;
}

message Extension {
  string name             = 1;     // "AHottie"
  string package_name     = 2;     // "eu.kanade.tachiyomi.extension.all.ahottie"
  Artifacts artifacts     = 3;
  string lib_version      = 4;     // "1.6", "1.4"
  uint64 version_code     = 5;     // 106004
  string version_name     = 6;     // "1.6.4"
  uint32 content_rating   = 7;     // 3-valued, see below
  repeated Source sources = 8;
}

message Artifacts {
  string apk_url  = 1;
  string icon_url = 2;
  string jar_url  = 501;           // note the gap
}

message Source {
  uint64 id           = 1;         // 6289731484943315811
  string name         = 2;
  string lang         = 3;         // "all", "en", "id", "ja", ...
  string base_url     = 4;
  string alt_base_url = 5;         // optional, 594 of 2212
}
```

## Notes per field

**`signing_key_sha256` (1.3)** is the key the repository declares it signs
with. It is a convenience for the trust prompt, **not** a substitute for
fingerprinting the downloaded APK — a repository asserting its own key proves
nothing (§5.5).

**`lib_version` (Extension.4)** is the `extensions-lib` version the extension
was built against. Observed values here were `1.4` and `1.6`. This is exactly
the compatibility gate §5.2 requires, delivered by the index itself rather than
read out of the APK manifest.

**`version_code` (Extension.5)** encodes the lib version alongside the patch
level: `1.6.4` → `106004`, `1.4.10` → `104010`, i.e. `L_MM_PPP`. Do not treat
it as an opaque counter when comparing across lib versions.

**`jar_url` (Artifacts.501)** points at a `.jar` built from the same source as
the APK. Field number 501 sits in a high range, suggesting a later addition.
Mimasu does not use it; it is recorded because it exists and may matter if the
ecosystem moves away from APK packaging.

**`version_code` and `lang`** are the only fields safe to sort or group by;
`Source.id` is a 64-bit hash, not a sequence.

**One extension commonly exposes many sources.** "Akuma" declares 27, one per
language. Any UI that assumes one source per extension is wrong.

## Open items

**`content_rating` (Extension.7) is not confirmed.** It is present on all 1,396
entries — so it is never the proto3 default of 0 — with this spread:

| value | count |
|---|---|
| 1 | 580 |
| 2 | 430 |
| 3 | 386 |

It does not correlate with source count or artifact count. Both adult
extensions sampled by hand (`AHottie`, `Akuma`) carry `3`, so the leading
hypothesis is a content rating where `3` means NSFW and `1` means safe. That
would give the Settings "Show NSFW sources" toggle something to filter on.

**This remains a hypothesis.** The raw integer is preserved in
`ExtensionEntry.contentRating` and no behaviour depends on it. Confirm it
against a repository that publishes a real catalogue in both formats, where the
JSON `nsfw` field can be compared directly.

**`alt_base_url` (Source.5) purpose is unconfirmed.** Present on 594 of 2,212
sources; in every sampled case it was byte-identical to `base_url`. Possibly a
declared-versus-overridable base URL distinction.

## Robustness

The parser reads by field number and skips fields it does not recognise, which
is what protobuf is designed for. A repository adding fields cannot break it. A
corrupt individual entry is dropped rather than failing the whole index (§6.4),
and only a payload that is not decodable in any supported format raises.
