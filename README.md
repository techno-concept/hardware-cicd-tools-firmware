# hardware-cicd-tools-firmware

This repository provides tooling, scripts, and Actions for managing firmware builds, releases, and security (Firmware Signing) across the [@techno-concept](https://github.com/techno-concept) organization.

## Prerequisites

To use the scripts in this repository, you must have the following tools installed: **AWS CLI** (configured with appropriate credentials), **jq** (for JSON parsing), and **OpenSSL** (for key management). The firmware verification script also requires the `crc32` utility.

## Firmware Securisation & Signing (AWS KMS)

To comply with our latest security guidelines, firmware binaries must be cryptographically signed using an ECC P-256 key stored securely inside AWS KMS.

*   **[Administrator Documentation](docs/aws-kms-setup-guide.md)**: Guide to generating a private key locally, importing it into an AWS KMS Hardware Security Module, and configuring the CI/CD policies.

*   **[Developer Documentation](docs/aws-kms-developer-guide.md)**: Instructions for developers on how to configure their local AWS credentials to test and sign firmware locally with maximum safety.

### Core Scripts

- [`generate-keys.sh`](generate-keys.sh): Generates an ECC P-256 private key and its corresponding public key.
- [`import-key-into-aws.sh`](import-key-into-aws.sh): Safely imports the generated private key into AWS KMS and creates an easily referenceable Alias.
- [`create-or-update-kms-sign-policy.sh`](create-or-update-kms-sign-policy.sh): Creates or updates the IAM Policy for KMS signature.
- [`create-or-update-github-signer-role.sh`](create-or-update-github-signer-role.sh): Creates or updates the dual Trust Policy Role (`githubSigner`) for GitHub Actions and local developers.

---

## Composite actions

This project also provides the following composite actions:

- [`techno-concept/hardware-cicd-tools-firmware/actions/github/release/create`](#github-release-create)
- [`techno-concept/hardware-cicd-tools-firmware/actions/github/firmware/build-docker`](#github-firmware-build-docker)

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

---

### <a name="github-firmware-build-docker"> `techno-concept/hardware-cicd-tools-firmware/actions/github/firmware/build-docker`

This action builds a firmware using a Docker container.

```yaml
- name: "Build firmware"
  uses: "techno-concept/hardware-cicd-tools-firmware/actions/github/firmware/build-docker@1.0.0"
  with:
    project-name: "my-project"
```

For details, see [`actions/github/firmware/build-docker/action.yml`](actions/github/firmware/build-docker/action.yml).

#### Inputs

- `project-name`, required: The name of the project to build.
- `build-type`, optional: The type of build (Release, Debug). Defaults to `Release`.

