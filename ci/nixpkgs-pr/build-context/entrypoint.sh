#!/usr/bin/env bash

set -e -o pipefail -u

git init
git remote add NixOS https://github.com/NixOS/nixpkgs.git
git remote add VirtusLab https://${GITHUB_TOKEN}@github.com/VirtusLab/nixpkgs.git

set -x
if [[ $DO_PUSH == true ]]; then
  git fetch --progress NixOS master
else
  # We don't need to fetch any past history of NixOS/master if we're not opening a PR
  git fetch --depth=1 NixOS master
fi
git checkout -B master NixOS/master

expression_path=pkgs/applications/version-management/git-and-tools/git-machete/default.nix
pypi_url=$(
  curl -s https://$PYPI_HOST/pypi/git-machete/v$VERSION/json \
    | jq --raw-output '.urls | map(select(.packagetype == "sdist")) | .[0].url'
)
tarball_sha256=$(nix-prefetch-url --type sha256 "$pypi_url")
existing_version=$(grep 'version = \".*\";' $expression_path | cut -d '"' -f2)
sed -i "s/version = \".*\";/version = \"$VERSION\";/" $expression_path
sed -i "s/sha256 = \".*\";/sha256 = \"$tarball_sha256\";/" $expression_path

nix-build -A gitAndTools.git-machete || {
  ls -l /nix/store/3v3ajxd7cv60h6j608x8xka017pzr9gd-git-machete-3.3.0/bin/ || true
  sed -i 's/assertExecutable() {/& set -x; echo Hello for \$1; ls -l \$1 || true; id; /' /nix/store/8b9q1c34dxq8p72q71x77yh3hd924yn1-hook/nix-support/setup-hook
  nix-build -A gitAndTools.git-machete
}
nix-env -f . -iA gitAndTools.git-machete
installed_version=$(git machete --version)
[[ ${installed_version/git-machete version /} = $VERSION ]]

branch=git-machete-$VERSION
git checkout -b $branch
git add $expression_path
title="gitAndTools.git-machete: $existing_version -> $VERSION"
commit_message=$(echo "$title"; echo; cat /root/commit-message.md)
git config user.email "gitmachete@virtuslab.com"
git config user.name "Git Machete Release Bot"
git commit -m "$commit_message"

# We don't want to @-mention the NixOS maintainers in commit messages (only in PR description),
# see https://github.com/VirtusLab/git-machete/issues/127
pr_description=$(echo "$title"; echo; cat /root/pr-description.md)
if [[ $DO_PUSH == true ]]; then
  git push VirtusLab $branch
  # 'hub pull-request' relies on GITHUB_TOKEN env var (not on the git remote's URL as 'git push' does) for authentication.
  hub pull-request \
    --base NixOS:master \
    --head VirtusLab:$branch \
    --message "$pr_description" \
    --labels='10.rebuild-darwin: 1-10,10.rebuild-linux: 1-10,11.by: upstream-developer'
  # Deliberately not setting `--reviewer`, since it's not strictly needed
  # and caused non-trivial issues with access of personal OAuth token to organization-owned repo.
else
  echo "Refraining from pushing the changes and opening a PR since it's a dry run"
fi
