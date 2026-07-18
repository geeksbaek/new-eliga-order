#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
ios_dir=${script_dir:h}
project_yml="$ios_dir/project.yml"
project_file="$ios_dir/NewEligaOrder.xcodeproj/project.pbxproj"
bump=${1:-}

if [[ ! "$bump" =~ '^(major|minor|patch|build)$' ]]; then
  print -u2 "사용법: $0 major|minor|patch|build"
  exit 64
fi

current_version=$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$project_yml")
current_build=$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$project_yml")

if [[ ! "$current_version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || ! "$current_build" =~ '^[0-9]+$' ]]; then
  print -u2 "현재 버전을 해석할 수 없습니다: $current_version ($current_build)"
  exit 65
fi

version_parts=("${(@s:.:)current_version}")
major=${version_parts[1]}
minor=${version_parts[2]}
patch=${version_parts[3]:-0}
new_build=$((current_build + 1))

case "$bump" in
  major)
    new_version="$((major + 1)).0.0"
    ;;
  minor)
    new_version="$major.$((minor + 1)).0"
    ;;
  patch)
    new_version="$major.$minor.$((patch + 1))"
    ;;
  build)
    new_version="$major.$minor.$patch"
    ;;
esac

NEW_VERSION="$new_version" NEW_BUILD="$new_build" /usr/bin/perl -0pi -e '
  s/(CURRENT_PROJECT_VERSION:\s*)\d+/${1}$ENV{NEW_BUILD}/g;
  s/(MARKETING_VERSION:\s*)[0-9.]+/${1}$ENV{NEW_VERSION}/g;
' "$project_yml"

NEW_VERSION="$new_version" NEW_BUILD="$new_build" /usr/bin/perl -0pi -e '
  s/(CURRENT_PROJECT_VERSION = )[^;]+;/${1}$ENV{NEW_BUILD};/g;
  s/(MARKETING_VERSION = )[^;]+;/${1}$ENV{NEW_VERSION};/g;
' "$project_file"

print "엘리가오더 버전: $current_version ($current_build) → $new_version ($new_build)"
