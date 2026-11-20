---
name: oci-digest
description: Get the sha256 digest for an OCI container image tag (linux/amd64). Use when pinning a container image to a digest in a NixOS module, or when verifying an image reference before deploying.
argument-hint: <registry/image:tag>
allowed-tools: Bash(nix run nixpkgs#skopeo *)
user-invocable: true
---

Get the linux/amd64 digest for the OCI image `$ARGUMENTS`.

Run:

```bash
raw=$(nix run nixpkgs#skopeo -- inspect --raw docker://$ARGUMENTS)
if echo "$raw" | nix run nixpkgs#jq -- -e '.manifests' >/dev/null; then
  # multi-arch index: pick the linux/amd64 manifest digest
  echo "$raw" | nix run nixpkgs#jq -- -r '.manifests[] | select(.platform.os=="linux" and .platform.architecture=="amd64") | .digest'
else
  # single-platform image: the manifest digest (NOT .config.digest — that is the
  # image config blob and is not a valid image reference)
  nix run nixpkgs#skopeo -- inspect --format '{{.Digest}}' docker://$ARGUMENTS
fi
```

Report the digest and show the full pinned image reference to use in the NixOS module:

```
<registry/image:tag>@<digest>
```

If the image is not found or the registry is unreachable, say so and suggest checking the tag exists with:
```bash
nix run nixpkgs#skopeo -- list-tags docker://<registry/image>
```
