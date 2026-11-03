#!/bin/sh
# 使い方: sh deploy.sh   （Webをビルドして GitHub Pages に公開。ソースの更新は別途 git push）
set -e
export MSYS_NO_PATHCONV=1
flutter build web --release --base-href /NatureWalk/
D=$(mktemp -d)
cp -r build/web/. "$D"
touch "$D/.nojekyll"
cd "$D"
git init -q -b gh-pages
git config user.name "Ninjinman"
git config user.email "Ninjinman@users.noreply.github.com"
git add -A
git commit -q -m "deploy"
git push -f https://github.com/Ninjinman/NatureWalk.git gh-pages
echo "公開しました: https://ninjinman.github.io/NatureWalk/"
