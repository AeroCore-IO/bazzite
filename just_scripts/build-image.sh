#!/usr/bin/bash
set -euo pipefail
if [[ -z ${project_root:-} ]]; then
    project_root=$(git rev-parse --show-toplevel)
fi
if [[ -z ${git_branch:-} ]]; then
    git_branch=$(git branch --show-current)
fi

# Get Inputs
target=${1:-}
image=${2:-}

# Set image/target/version based on inputs
# shellcheck disable=SC2154,SC1091
. "${project_root}/just_scripts/get-defaults.sh"

# Get info
container_mgr=$(just _container_mgr)
tag=${LOCAL_TAG:-$(just _tag "${image}")}

if [[ ${image} =~ "gnome" ]]; then
    base_image="silverblue"
else
    base_image="kinoite"
fi

fedora_version=${FEDORA_VERSION:-${latest}}
arch=${ARCH:-x86_64}
remote_owner=$(git config --get remote.origin.url | sed -E 's#.*[:/]([^/]+)/[^/]+(.git)?$#\1#' | tr '[:upper:]' '[:lower:]')
if [[ -z ${remote_owner} || ${remote_owner} == "git" ]]; then
    remote_owner="aerocore-io"
fi
image_vendor=${IMAGE_VENDOR:-${IMAGE_NAMESPACE:-${remote_owner}}}
image_branch=${IMAGE_BRANCH:-${git_branch:-local}}
version_tag=${VERSION_TAG:-local-${fedora_version}-${git_branch:-detached}}
version_pretty=${VERSION_PRETTY:-"Local ${fedora_version} (${git_branch:-detached})"}
nvidia_base=${NVIDIA_BASE:-${target}}
nvidia_flavor=${NVIDIA_FLAVOR:-nvidia-lts}
base_image_ref=${BASE_IMAGE:-ghcr.io/ublue-os/${base_image}-main:${fedora_version}}

build_args_dir="${project_root}/.local/build-args"
mkdir -p "${build_args_dir}"
build_args_file="${BUILD_ARGS_FILE:-${build_args_dir}/${image}.txt}"

{
    echo "BASE_IMAGE_NAME=${base_image}"
    echo "FEDORA_VERSION=${fedora_version}"
    echo "BASE_IMAGE=${base_image_ref}"
    echo "IMAGE_NAME=${image}"
    echo "IMAGE_VENDOR=${image_vendor}"
    echo "IMAGE_BRANCH=${image_branch}"
    if grep -q '^ARG KERNEL_REF=' "${project_root}/Containerfile"; then
        echo "KERNEL_REF=${KERNEL_REF:-ghcr.io/bazzite-org/kernel-bazzite:latest-f${fedora_version}-${arch}}"
        echo "NVIDIA_REF=${NVIDIA_REF:-none}"
    else
        echo "KERNEL_FLAVOR=${KERNEL_FLAVOR:-ogc}"
        echo "KERNEL_VERSION=${KERNEL_VERSION:-6.19.14-ogc2.1.fc44.x86_64}"
        echo "NVIDIA_FLAVOR=${nvidia_flavor}"
    fi
    echo "NVIDIA_BASE=${nvidia_base}"
    echo "SHA_HEAD_SHORT=${SHA_HEAD_SHORT:-$(git -C "${project_root}" rev-parse --short HEAD)}"
    echo "VERSION_TAG=${version_tag}"
    echo "VERSION_PRETTY=${version_pretty}"
    echo "ARCH=${arch}"
    [[ -n ${FLATPAK_REMOTE_URL:-} ]] && echo "FLATPAK_REMOTE_URL=${FLATPAK_REMOTE_URL}"
    [[ -n ${HOMEBREW_BOTTLE_DOMAIN:-} ]] && echo "HOMEBREW_BOTTLE_DOMAIN=${HOMEBREW_BOTTLE_DOMAIN}"
    [[ -n ${HOMEBREW_API_DOMAIN:-} ]] && echo "HOMEBREW_API_DOMAIN=${HOMEBREW_API_DOMAIN}"
    [[ -n ${DECKY_MIRROR_HOST:-} ]] && echo "DECKY_MIRROR_HOST=${DECKY_MIRROR_HOST}"
    [[ -n ${DECKY_PLUGIN_MIRROR_HOST:-} ]] && echo "DECKY_PLUGIN_MIRROR_HOST=${DECKY_PLUGIN_MIRROR_HOST}"
    [[ -n ${DECKY_PLUGIN_ID:-} ]] && echo "DECKY_PLUGIN_ID=${DECKY_PLUGIN_ID}"
} > "${build_args_file}"

secret_args=()
if [[ -n ${GITHUB_TOKEN:-} ]]; then
    secret_args+=(--secret id=GITHUB_TOKEN,env=GITHUB_TOKEN)
fi

# Build Image
echo "Building ${image} from ${target} with ${container_mgr}"
echo "Build args: ${build_args_file}"

build_cmd=(
    "$container_mgr" build
)
if [[ ${container_mgr} == "buildah" || ${container_mgr} == "podman" ]]; then
    build_cmd+=(--layers)
fi
build_cmd+=(
    -f Containerfile
    --build-arg-file="${build_args_file}"
    "${secret_args[@]}"
    --target="${target}"
    --tag "localhost/${tag}:${fedora_version}-${git_branch:-local}"
    "${project_root}"
)

if [[ ${BUILD_DRY_RUN:-0} == "1" ]]; then
    printf 'Command:'
    printf ' %q' "${build_cmd[@]}"
    printf '\n'
    exit 0
fi

"${build_cmd[@]}"
