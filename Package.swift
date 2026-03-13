// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// RainbowCursor Package Manifest
// 负责：定义 macOS 可执行目标与最低系统版本约束。
// 说明：当前项目以单一可执行目标为主，源码入口位于 Sources/CursorTrailBar/CursorTrailBar.swift。

import PackageDescription

let package = Package(
    name: "RainbowCursor",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "RainbowCursor",
            path: "Sources/CursorTrailBar"
        ),
    ]
)
