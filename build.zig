const std = @import("std");
const zrender = @import("ZRender/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ecsModule = b.createModule(.{
        .root_source_file = .{ .path = "ZEngine/zig-ecs/src/ecs.zig" },
        .target = target,
        .optimize = optimize,
    });
    const zengineModule = b.createModule(.{
        .root_source_file = .{ .path = "ZEngine/src/zengine.zig" },
        .target = target,
        .optimize = optimize,
    });
    zengineModule.addImport("ecs", ecsModule);
    const zlmModule = b.createModule(.{
        .root_source_file = .{ .path = "zlm/src/zlm.zig" },
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "AcerolaGameJam",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("ecs", ecsModule);
    exe.root_module.addImport("zengine", zengineModule);
    exe.root_module.addImport("zlm", zlmModule);
    const zrenderLib = try zrender.link("ZRender", b, zengineModule, ecsModule, .{ .KmakeOptions = .{}, .shaders = &[_]zrender.Shader{
        .{ .sourcePath = "src/shaders/shader.frag.glsl", .destPath = "src/shaderBin/shader.frag" },
        .{ .sourcePath = "src/shaders/shader.vert.glsl", .destPath = "src/shaderBin/shader.vert" },
    }, .target = target, .optimize = optimize });
    exe.root_module.addImport("zrender", &zrenderLib.root_module);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    const runStep = b.step("run", "run the example");
    runStep.dependOn(&run.step);
}
