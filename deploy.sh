#!/bin/sh
# 使い方: sh deploy.sh   （Webをビルドして GitHub Pages に公開。ソースの更新は別途 git push）
set -e
export MSYS_NO_PATHCONV=1
flutter build web --release --base-href /NatureWalk/
D=$(mktemp -d)
cp -r build/web/. "$D"
touch "$D/.nojekyll"
# GitHub Pages は max-age=600 で配信するため、更新のたびにURLを変えて古いキャッシュを使わせない
V=$(date +%s)
sed -i "s#flutter_bootstrap.js#flutter_bootstrap.js?v=$V#" "$D/index.html"
sed -i "s#main.dart.js\"#main.dart.js?v=$V\"#g" "$D/flutter_bootstrap.js"
cd "$D"
git init -q -b gh-pages
git config user.name "Ninjinman"
git config user.email "Ninjinman@users.noreply.github.com"
git add -A
git commit -q -m "deploy"
git push -f https://github.com/Ninjinman/NatureWalk.git gh-pages
echo "公開しました: https://ninjinman.github.io/NatureWalk/"
