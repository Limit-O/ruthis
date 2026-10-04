#!/bin/sh
# 把仓库里的官方磁贴安装到用户磁贴目录（外置化后官方磁贴与第三方磁贴同机制）
# 用法：scripts/install-tiles.sh
set -e
DEST="${HOME}/.local/share/ruthis/tiles"
mkdir -p "$DEST"
for d in tiles/*/; do
    name=$(basename "$d")
    [ "$name" = "_generic" ] && continue   # 通用渲染器属于外壳，已编入二进制
    cp -r "$d" "$DEST/"
    echo "已安装: $name"
done
echo "磁贴目录: $DEST"
