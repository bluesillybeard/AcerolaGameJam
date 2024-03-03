const std = @import("std");
const zengine = @import("zengine");
const zrender = @import("zrender");
const zlm = @import("zlm");
const ecs = @import("ecs");

// there is only one shader so only one type of vertex is needed
const Vertex = struct {
    pub const attributes = [_]zrender.NamedAttribute{
        .{ .name = "pos", .type = .f32x3 },
        .{ .name = "texCoord", .type = .f32x2 },
    };
    x: f32,
    y: f32,
    z: f32,
    texX: f32,
    texY: f32,
};

// A "normal" ZEngine game should split functionality across many systems for better organization.
// This is a game jam so I don't give a crap.
const AcerolaGameJamSystem = struct {
    pub const name: []const u8 = "acerola_game_jam";
    pub const components = [_]type{};
    pub fn comptimeVerification(comptime options: zengine.ZEngineComptimeOptions) bool {
        // verification is for loosers. Even though I'm the guy who created this verification function in the first place...
        _ = options;
        return true;
    }

    pub fn init(staticAllocator: std.mem.Allocator, heapAllocator: std.mem.Allocator) @This() {
        _ = staticAllocator;
        return .{
            .allocator = heapAllocator,
            .timeSinceStart = 0,
            // these undefines are ok since they are set within SystemInit
            .quadMesh = undefined,
            .texture = undefined,
            .pipeline = undefined,
            .uniforms = undefined,
            .entity = undefined,
        };
    }

    pub fn systemInitGlobal(this: *@This(), registries: *zengine.RegistrySet, settings: anytype) !void {
        const renderSystem = registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        // create the pipeline
        this.pipeline = try renderSystem.createPipeline(@embedFile("shaderBin/shader.vert"), @embedFile("shaderBin/shader.frag"), .{
            .attributes = &Vertex.attributes,
            .uniforms = &[_]zrender.NamedUniformTag{ .{ .name = "transform", .tag = .mat4 }, .{ .name = "tex", .tag = .texture } },
        });
        // load a quad mesh
        // This jam was written before ZRender had mesh loading functions so the mesh has to be loaded in pure code.
        // You know, if this jam was like a week later then I would have had the time to implement that into ZRender.
        this.quadMesh = try renderSystem.loadMesh(Vertex, &[_]Vertex{
            .{ .x = -1.0, .y = -1.0, .z = 0, .texX = 0.0, .texY = 1.0 }, //0 top left
            .{ .x = -1.0, .y = 1.0, .z = 0, .texX = 0.0, .texY = 0.0 }, //1 bottom left
            .{ .x = 1.0, .y = 1.0, .z = 0, .texX = 1.0, .texY = 0.0 }, //2 bottom right
            .{ .x = 1.0, .y = -1.0, .z = 0, .texX = 1.0, .texY = 1.0 }, //3 top right
        }, &[_]u16{
            0, 1, 2, 2, 3, 0,
        }, this.pipeline);

        const texture = try renderSystem.loadTexture(@embedFile("assets/fruit.png"));
        this.uniforms[0] = .{ .mat4 = zrender.Mat4.identity };
        this.uniforms[1] = .{ .texture = texture };
        this.entity = registries.globalEcsRegistry.create();
        registries.globalEcsRegistry.add(this.entity, zrender.RenderComponent{
            .pipeline = this.pipeline,
            .mesh = this.quadMesh,
            .uniforms = &this.uniforms,
        });
        renderSystem.onUpdate.sink().connectBound(this, "update");
        _ = settings;
    }

    pub fn update(this: *@This(), args: zrender.OnUpdateEventArgs) void {
        this.timeSinceStart += args.delta;
        const renderSystem = args.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        // create the zlm mat4
        var transform = zlm.Mat4.identity;
        // object transformations
        const angle = @as(f32, @floatFromInt(this.timeSinceStart)) / (std.time.us_per_s * 10);
        transform = transform.mul(zlm.Mat4.createAngleAxis(zlm.Vec3.unitZ, angle));
        // TODO: define camera parameters elsewhere
        const resolution = renderSystem.getWindowResolution();
        // Gotta say, Zig's float-int casting is such a pain
        const aspect: f32 = @as(f32, @floatFromInt(resolution.height)) / @as(f32, @floatFromInt(resolution.width));
        const cameraCenter = zlm.vec2(0, 0);
        const cameraRadiusX: f32 = 1;
        const cameraRadiusY: f32 = cameraRadiusX * aspect;
        // camera transformations
        transform = transform.mul(zlm.Mat4.createLook(zlm.Vec3{ .x = cameraCenter.x, .y = cameraCenter.y, .z = 0.5 }, zlm.Vec3.unitZ, zlm.Vec3.unitY));
        transform = transform.mul(zlm.Mat4.createOrthogonal(-cameraRadiusX, cameraRadiusX, -cameraRadiusY, cameraRadiusY, 0.01, 10));
        const renderComponent = args.registries.globalEcsRegistry.get(zrender.RenderComponent, this.entity);
        renderComponent.uniforms[0] = .{ .mat4 = zlmToZrenderMat4(transform) };
    }

    pub fn systemDeinitGlobal(this: *@This(), registries: *zengine.RegistrySet) void {
        _ = registries;
        _ = this;
    }

    pub fn deinit(this: *@This()) void {
        _ = this;
    }

    fn zlmToZrenderMat4(matrix: zlm.Mat4) zrender.Mat4 {
        return zrender.Mat4{
            .m00 = matrix.fields[0][0],
            .m01 = matrix.fields[1][0],
            .m02 = matrix.fields[2][0],
            .m03 = matrix.fields[3][0],
            .m10 = matrix.fields[0][1],
            .m11 = matrix.fields[1][1],
            .m12 = matrix.fields[2][1],
            .m13 = matrix.fields[3][1],
            .m20 = matrix.fields[0][2],
            .m21 = matrix.fields[1][2],
            .m22 = matrix.fields[2][2],
            .m23 = matrix.fields[3][2],
            .m30 = matrix.fields[0][3],
            .m31 = matrix.fields[1][3],
            .m32 = matrix.fields[2][3],
            .m33 = matrix.fields[3][3],
        };
    }

    fn zrenderToZlmMat4(m: zrender.Mat4) zlm.Mat4 {
        return zrender.Mat4{ .fields = [_][4]f32{
            [_]f32{ m.m00, m.m10, m.m20, m.m30 },
            [_]f32{ m.m01, m.m11, m.m21, m.m31 },
            [_]f32{ m.m02, m.m12, m.m22, m.m32 },
            [_]f32{ m.m03, m.m13, m.m23, m.m33 },
        } };
    }
    allocator: std.mem.Allocator,
    // If this wasn't a jam, I would write an actual asset manager instead of just plonking them here
    quadMesh: zrender.MeshHandle,
    texture: zrender.TextureHandle,
    pipeline: zrender.PipelineHandle,
    // TODO: move into component
    uniforms: [2]zrender.Uniform,
    entity: ecs.Entity,
    timeSinceStart: i64,
};

pub fn main() !void {
    var allocatorObj = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = allocatorObj.deinit();
    const allocator = allocatorObj.allocator();

    const ZEngine = zengine.ZEngine(.{
        .globalSystems = &[_]type{ zrender.ZRenderSystem, AcerolaGameJamSystem },
        .localSystems = &[_]type{},
    });
    var engine = try ZEngine.init(allocator, .{});
    defer engine.deinit();
    var zrenderSystem = engine.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
    zrenderSystem.run();
}
