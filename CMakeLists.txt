cmake_minimum_required(VERSION 3.21)
project(ruthis LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick DBus Network)
find_package(LayerShellQt REQUIRED)

qt_add_executable(ruthis
    src/main.cpp
    src/applist.h
    src/audioinfo.h
    src/datasource.h
    src/launcher.h
    src/mediainfo.h
    src/pinnedsurfaces.h
    src/tilestore.h
    src/sysinfo.h
    src/iconprovider.h
    src/tileregistry.h
    src/windowsbridge.h
)

qt_add_resources(ruthis "qml" PREFIX "/" FILES src/Main.qml src/TileHost.qml)
qt_add_resources(ruthis "kwin" PREFIX "/" FILES kwin/kwin-windows.js)

# 磁贴即插件：官方磁贴不编入二进制，与第三方磁贴同一机制（安装到磁贴目录，
# 见 scripts/install-tiles.sh 与 docs/tiles.md）。仅通用声明式渲染器属于外壳。
qt_add_resources(ruthis "tiles-generic" PREFIX "/" FILES tiles/_generic/Tile.qml)

# 翻转切换器的纵深模糊用 QtQuick.Effects 的 MultiEffect（Qt 6.11 实测：
# QML 自定义 ShaderEffect 静默不渲染，自定义 qsb 着色器路线不可用，勿再引入）

# kenney CC0 图标包随仓库分发，编译期嵌入二进制（assets/kenney/{White,Black}/*.png）
file(GLOB KENNEY_ICONS CONFIGURE_DEPENDS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
    assets/kenney/White/*.png
    assets/kenney/Black/*.png)
qt_add_resources(ruthis "kenney" PREFIX "/" FILES assets/kenney/license.txt ${KENNEY_ICONS})

target_link_libraries(ruthis PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::DBus
    Qt6::Network
    LayerShellQt::Interface
)

target_compile_definitions(ruthis PRIVATE
    RUTHIS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)
