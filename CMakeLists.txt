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
    src/launcher.h
    src/tilestore.h
    src/sysinfo.h
    src/iconprovider.h
    src/windowsbridge.h
    src/swaybridge.h
)

qt_add_resources(ruthis "qml" PREFIX "/" FILES src/Main.qml)
qt_add_resources(ruthis "kwin" PREFIX "/" FILES kwin/kwin-windows.js)

target_link_libraries(ruthis PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::DBus
    Qt6::Network
    LayerShellQt::Interface
)
