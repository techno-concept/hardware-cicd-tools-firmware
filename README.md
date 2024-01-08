# hardware-cicd-tools-firmware

This project provides composite actions for the [@techno-concept](https://github.com/techno-concept) organization.

## Composite actions

This project provides the following composite actions:

- [`techno-concept/hardware-cicd-tools-firmware/actions/github/release/create`](#github-release-create)

### <a name="github-release-create"> `techno-concept/hardware-cicd-tools-firmware/actions/github/release/create`

This action creates a release.

This is useful when you automatically want to create releases with [automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes).

```yaml

name: "Release"

on:
  push:
    tags:
      - "**"

jobs:
  release:
    name: "Release"

    runs-on: "ubuntu-latest"

    steps:
      - name: "Create release"
        uses: "techno-concept/hardware-cicd-tools-firmware/actions/github/release/create@1.0.0"
        with:
          github-token: "${{ secrets.GITHUB_TOKEN }}"
```

For details, see [`actions/github/release/create/action.yml`](actions/github/release/create/action.yml).

#### Inputs

- `github-token`, required: The GitHub token of a user with permission to create a release.
- `release-draft`, optional: Whether to create a draft release. Defaults to `false`.
- `release-pre-release`, optional: Whether to create a pre-release. Defaults to `false`.

#### Outputs

- `RELEASE_ID`: environment variable contains the release identifier.
- `RELEASE_HTML_URL`: environment variable contains the HTML URL to the release.
- `RELEASE_UPLOAD_URL`: environment variable contains the URL for uploading release assets.

#### Side Effects

A release is created by the user who owns the GitHub token specified with the `github-token` input.
