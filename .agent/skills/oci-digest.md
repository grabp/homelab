---
name: oci-digest
description: Get the sha256 digest for an OCI container image tag (linux/amd64). Use when pinning a container image to a digest in a NixOS module, or when verifying an image reference before deploying.
argument-hint: <registry/image:tag>
disable-model-invocation: true
allowed-tools: Bash(nix run nixpkgs#skopeo *)
---

Get the linux/amd64 digest for the OCI image `$ARGUMENTS`.

Run:

```bash
nix run nixpkgs#skopeo -- inspect --raw docker://$ARGUMENTS \
  | nix run nixpkgs#jq -- '
      if .manifests then
        .manifests[] | select(.platform.os=="linux" and .platform.architecture=="amd64") | .digest
      else
        .config.digest
      end'
```

Report the digest and show the full pinned image reference to use in the NixOS module:

```
<registry/image:tag>@<digest>
```

If the image is not found or the registry is unreachable, say so and suggest checking the tag exists with:
```bash
nix run nixpkgs#skopeo -- list-tags docker://<registry/image>
```
