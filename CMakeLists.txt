cmake_minimum_required(VERSION 3.21)
project(ruthis LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick DBus)
find_package(LayerShellQt REQUIRED)

qt_add_executable(ruthis
    src/main.cpp
    src/applist.h
    src/audioinfo.h
    src/launcher.h
    src/mediainfo.h
    src/tilestore.h
    src/sysinfo.h
    src/iconprovider.h
    src/windowsbridge.h
)

qt_add_resources(ruthis "qml" PREFIX "/" FILES src/Main.qml)
qt_add_resources(ruthis "kwin" PREFIX "/" FILES kwin/kwin-windows.js)

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
    LayerShellQt::Interface
)

target_compile_definitions(ruthis PRIVATE
    RUTHIS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)
