const std = @import("std");
const zengine = @import("zengine");
const zrender = @import("zrender");
const zlm = @import("zlm");
const ecs = @import("ecs");

// All spatial units are in screens per second.
// The viewport of the player is normalized so the smaller dimetion is 1, and the larger dimention is >=1.
const gravity = -2.0;

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

const FruitComponent = struct {
    uniforms: [2] zrender.Uniform,
    fruit: Fruit,
};

const Fruit = struct {
    xPos: f32,
    yPos: f32,
    lastXPos: f32,
    lastYPos: f32,
    angle: f32,
    xVel: f32,
    yVel: f32,
    aVel: f32,
    scale: f32,
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
            .fruitSpawnCountown = 0,
            // these undefines are ok since they are set within SystemInit
            .quadMesh = undefined,
            .fruitTexture = undefined,
            .bgTexture = undefined,
            .fgTexture = undefined,
            .pipeline = undefined,
            .rand = undefined,
            .bgEntity = undefined,
            .bgUniforms = undefined,
            .fgEntity = undefined,
            .fgUniforms = undefined,
            .cursorX = 0,
            .cursorY = 0,
            .lastCursorX = 0,
            .lastCursorY = 0,
            .lastCursorUpdate = 0,
            .cursorVelX = 0,
            .cursorVelY = 0,
        };
    }

    pub fn systemInitGlobal(this: *@This(), registries: *zengine.RegistrySet, settings: anytype) !void {
        this.rand = std.rand.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
        const renderSystem = registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        // create the pipeline
        this.pipeline = try renderSystem.createPipeline(@embedFile("shaderBin/shader.vert"), @embedFile("shaderBin/shader.frag"), .{
            .attributes = &Vertex.attributes,
            .uniforms = &[_]zrender.NamedUniformTag{ .{ .name = "transform", .tag = .mat4 }, .{ .name = "tex", .tag = .texture } },
        });
        // Load assets for fruit
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

        this.fruitTexture = try renderSystem.loadTexture(@embedFile("assets/fruit.png"));
        this.bgTexture = try renderSystem.loadTexture(@embedFile("assets/bg.png"));
        this.fgTexture = try renderSystem.loadTexture(@embedFile("assets/fg.png"));

        // background entity
        this.bgEntity = registries.globalEcsRegistry.create();
        registries.globalEcsRegistry.add(this.bgEntity, zrender.RenderComponent {
            .mesh = this.quadMesh,
            .pipeline = this.pipeline,
            .uniforms = &this.bgUniforms,
        });
        // TODO non-identity transform
        this.bgUniforms[0] = .{.mat4 = zrender.Mat4.identity};
        this.bgUniforms[1] = .{.texture = this.bgTexture};
        // foreground entity
        this.fgEntity = registries.globalEcsRegistry.create();
        registries.globalEcsRegistry.add(this.fgEntity, zrender.RenderComponent {
            .mesh = this.quadMesh,
            .pipeline = this.pipeline,
            .uniforms = &this.fgUniforms,
        });
        // TODO non-identity transform
        this.fgUniforms[0] = .{.mat4 = zrender.Mat4.identity};
        this.fgUniforms[1] = .{.texture = this.fgTexture};

        renderSystem.onFrame.sink().connectBound(this, "onFrame");
        renderSystem.onMousePress.sink().connectBound(this, "onClick");
        renderSystem.onMouseMove.sink().connectBound(this, "onMouseMove");
        _ = settings;
    }

    fn spawnFruit(this: *@This(), registries: *zengine.RegistrySet, texture: zrender.TextureHandle, fruit: Fruit) void {
        const entity = registries.globalEcsRegistry.create();
        registries.globalEcsRegistry.add(entity, FruitComponent {
            .uniforms = [_]zrender.Uniform{.{.mat4 = zrender.Mat4.identity}, .{.texture = texture}},
            .fruit = fruit,
        });
        const fruitComponent = registries.globalEcsRegistry.get(FruitComponent, entity);
        registries.globalEcsRegistry.add(entity, zrender.RenderComponent{
            .pipeline = this.pipeline,
            .mesh = this.quadMesh,
            .uniforms = &fruitComponent.uniforms,
        });
    }

    pub fn onFrame(this: *@This(), args: zrender.OnFrameEventArgs) void {
        this.timeSinceStart += args.delta;
        this.fruitSpawnCountown -= args.delta;
        var random = this.rand.random();
        // Every time @as(@floatFromInt) is needed, I am reminding you how silly this is
        const deltaSeconds: f32 = @as(f32, @floatFromInt(args.delta)) / std.time.us_per_s;
        const renderSystem = args.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;

        if(this.fruitSpawnCountown < 0) {
            this.spawnFruit(args.registries, this.fruitTexture, Fruit {
                .angle = 0,
                .aVel = random.float(f32) * 1.5 - (1.5 / 2.0),
                .scale = 0.07,
                .xPos = random.float(f32) * 2 - 1,
                .yPos = -1.5,
                // These are only used for detecting when the fruit is cut so it doesn't matter they don't match
                .lastXPos = 0,
                .lastYPos = -1.5,
                // TODO: bias this towards the middle of the screen
                .xVel = random.float(f32) * 1.0 - (1.0 / 2.0),
                .yVel = 3,
            });
            this.fruitSpawnCountown += 1 * std.time.us_per_s;
        }
        // camera transformations
        const cameraTransform = getCameraTransform(renderSystem.getWindowResolution());
        const view = args.registries.globalEcsRegistry.basicView(FruitComponent);
        var iterator = view.entityIterator();
        var fruitToRemove = std.ArrayList(ecs.Entity).init(this.allocator);
        defer fruitToRemove.deinit();
        while(iterator.next()) |entity| {
            // explicit type hint because zls isn't very good at comptime stuff
            const fruit: *FruitComponent = view.get(entity);
            // delete fruit that fall offscreen
            if(fruit.fruit.yPos < -1.5) {
                fruitToRemove.append(entity) catch @panic("Out of memory!");
                continue;
            }
            const renderComponent = args.registries.globalEcsRegistry.get(zrender.RenderComponent, entity);
            // Update the fruit
            fruit.fruit.yVel += gravity * deltaSeconds;
            fruit.fruit.lastXPos = fruit.fruit.xPos;
            fruit.fruit.lastYPos = fruit.fruit.yPos;
            fruit.fruit.yPos += fruit.fruit.yVel * deltaSeconds;
            fruit.fruit.xPos += fruit.fruit.xVel * deltaSeconds;
            fruit.fruit.angle += fruit.fruit.aVel * deltaSeconds;

            // If the fruit is near the cursor and the cursor is moving greater than a certain speed,
            // then that fruit gets deleted
            const fruitCursorDistance = segmentSegmentDistance(this.cursorX, this.cursorY, this.lastCursorX, this.lastCursorY, fruit.fruit.xPos, fruit.fruit.yPos, fruit.fruit.lastXPos, fruit.fruit.lastYPos);
            const cursorVelocity = this.cursorVelX * this.cursorVelX + this.cursorVelY * this.cursorVelY;
            if(fruitCursorDistance < fruit.fruit.scale and cursorVelocity > 0.2) {
                fruitToRemove.append(entity) catch @panic("Out of memory!");
                continue;
            }

            // Update the render component with the new fruit data
            const objectTransform = getFruitTransform(fruit.fruit);
            const transform = objectTransform.mul(cameraTransform);
            // Sometimes, the renderComponent's reference to uniforms is invalidated when the ECS expands things,
            // So, set the render component to the correct one
            renderComponent.uniforms = &fruit.uniforms;
            renderComponent.uniforms[0] = .{ .mat4 = zlmToZrenderMat4(transform) };
        }
        for(fruitToRemove.items) |entity| {
            args.registries.globalEcsRegistry.destroy(entity);
        }
        // update foreground and background transforms
        var bgTransform = zlm.Mat4.createTranslationXYZ(0, 0, 0.75);
        this.bgUniforms[0].mat4 = zlmToZrenderMat4(bgTransform.mul(cameraTransform));
        var fgTransform = zlm.Mat4.createTranslationXYZ(0, 0, 1.1);
        fgTransform = zlm.Mat4.createUniformScale(3).mul(fgTransform);
        this.fgUniforms[0].mat4 = zlmToZrenderMat4(fgTransform.mul(cameraTransform));
    }

    fn getFruitTransform(fruit: Fruit) zlm.Mat4 {
        var transform = zlm.Mat4.identity;
        
        transform = zlm.Mat4.createTranslationXYZ(fruit.xPos, fruit.yPos, 1).mul(transform);
        transform = zlm.Mat4.createAngleAxis(zlm.Vec3.unitZ, fruit.angle).mul(transform);
        transform = zlm.Mat4.createUniformScale(fruit.scale).mul(transform);
        
        return transform;
    }

    fn getCameraTransform(resolution: anytype) zlm.Mat4 {
        // Gotta say, Zig's float-int casting is such a pain
        const aspect: f32 = @as(f32, @floatFromInt(resolution.height)) / @as(f32, @floatFromInt(resolution.width));
        const cameraCenter = zlm.vec2(0, 0);
        
        var cameraRadiusX: f32 = 1;
        var cameraRadiusY: f32 = cameraRadiusX * aspect;
        if(resolution.width > resolution.height) {
            cameraRadiusY = 1;
            cameraRadiusX = cameraRadiusY / aspect;
        }
        var cameraTransform = zlm.Mat4.identity;
        cameraTransform = zlm.Mat4.createOrthogonal(-cameraRadiusX, cameraRadiusX, -cameraRadiusY, cameraRadiusY, 0.01, 10).mul(cameraTransform);
        cameraTransform = zlm.Mat4.createLook(zlm.Vec3{ .x = cameraCenter.x, .y = cameraCenter.y, .z = 0.5 }, zlm.Vec3.unitZ, zlm.Vec3.unitY).mul(cameraTransform);
        return cameraTransform;
    }

    // Returns the euclidian distance betwen the line defined by (p1x, p1y) (p2x, p2y), and the point (x, y)
    fn segmentPointDistance(x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) f32 {
        const A = x - x1;
        const B = y - y1;
        const C = x2 - x1;
        const D = y2 - y1;

        const dot = A * C + B * D;
        const len_sq = C * C + D * D;
        var param: f32 = -1;
        if (len_sq != 0) //in case of 0 length line
            param = dot / len_sq;

        var xx: f32 = undefined;
        var yy: f32 = undefined;

        if (param < 0) {
            xx = x1;
            yy = y1;
        }
        else if (param > 1) {
            xx = x2;
            yy = y2;
        }
        else {
            xx = x1 + param * C;
            yy = y1 + param * D;
        }

        const dx = x - xx;
        const dy = y - yy;
        return @sqrt(dx * dx + dy * dy);
    }

    /// Returns the distance between two line segments
    /// line 1 is (x11, y11) (x12, y12) and line 2 is (x21, y21) (x22, y22)
    fn segmentSegmentDistance(x11: f32, y11: f32, x12: f32, y12: f32, x21: f32, y21: f32, x22: f32, y22: f32) f32 {
        // if they intersect, the distance is zero
        if(segmentsIntersect(x11, y11, x12, y12, x21, y21, x22, y22)){
            return 0.0;
        }
        var distance = segmentPointDistance(x21, y21, x22, y22, x11, y11);
        // Min of 4 distances from segments to points
        distance = @min(segmentPointDistance(x21, y21, x22, y22, x12, y12), distance);
        distance = @min(segmentPointDistance(x11, y11, x12, y12, x21, y21), distance);
        distance = @min(segmentPointDistance(x11, y11, x12, y12, x22, y22), distance);
        return distance;
    }
    /// Returns true if two segments intersect, falst otherwise.
    /// line 1 is (x11, y11) (x12, y12) and line 2 is (x21, y21) (x22, y22)
    fn segmentsIntersect(x11: f32, y11: f32, x12: f32, y12: f32, x21: f32, y21: f32, x22: f32, y22: f32) bool {
        const dx1 = x12 - x11;
        const dy1 = y12 - y11;
        const dx2 = x22 - x21;
        const dy2 = y22 - y21;
        const delta = dx2 * dy1 - dy2 * dx1;
        if(delta == 0) return false;
        const s = (dx1 * (y21 - y11) + dy1 * (x11 - x21)) / delta;
        const t = (dx2 * (y11 - y21) + dy2 * (x21 - x11)) / (-delta);
        return (0 <= s and s <= 1) and (0 <= t and t <= 1);
    }
    fn pointPointdistance(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
        return @sqrt((x1-x2)*(x1-x2) + (y1-y2)*(y1-y2));
    }

    pub fn onClick(this: *@This(), args: zrender.OnMousePressEventArgs) void {
        _ = args;
        _ = this;
    }

    pub fn onMouseMove(this: *@This(), args: zrender.OnMouseMoveEventArgs) void {
            const cursorDeltaTimeMicros: f32 = @floatFromInt(args.time - this.lastCursorUpdate);
        const cursorDeltaTime = cursorDeltaTimeMicros / std.time.us_per_s;
        // If the delta is too small, then then ignore this movement
        if(cursorDeltaTimeMicros < 1000) return;
        // vec4 so it can be transformed by the camera
        const posInPixels = zlm.Vec4{.x = @floatFromInt(args.x), .y = @floatFromInt(args.y), .z = 0, .w = 1};
        const renderSystem = args.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        const resolution = renderSystem.getWindowResolution();
        // First, convert pixels to screen space
        const posInScreen = posInPixels.div(zlm.Vec4.new(@floatFromInt(resolution.width), @floatFromInt(resolution.height), 1, 1)).sub(zlm.Vec4.new(0.5, 0.5, 0, 0)).mul(zlm.Vec4.new(2, -2, 1, 1));
        const inverseCameraMatrix = getCameraTransform(resolution).invert() orelse unreachable;
        const posInWorld = posInScreen.transform(inverseCameraMatrix);
        this.lastCursorUpdate = args.time;
        this.lastCursorX = this.cursorX;
        this.lastCursorY = this.cursorY;
        this.cursorX = posInWorld.x;
        this.cursorY = posInWorld.y;
        this.cursorVelX = (this.cursorX - this.lastCursorX) / cursorDeltaTime;
        this.cursorVelY = (this.cursorY - this.lastCursorY) / cursorDeltaTime;
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
            .m01 = matrix.fields[0][1],
            .m02 = matrix.fields[0][2],
            .m03 = matrix.fields[0][3],
            .m10 = matrix.fields[1][0],
            .m11 = matrix.fields[1][1],
            .m12 = matrix.fields[1][2],
            .m13 = matrix.fields[1][3],
            .m20 = matrix.fields[2][0],
            .m21 = matrix.fields[2][1],
            .m22 = matrix.fields[2][2],
            .m23 = matrix.fields[2][3],
            .m30 = matrix.fields[3][0],
            .m31 = matrix.fields[3][1],
            .m32 = matrix.fields[3][2],
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
    fruitTexture: zrender.TextureHandle,
    bgTexture: zrender.TextureHandle,
    fgTexture: zrender.TextureHandle,
    pipeline: zrender.PipelineHandle,
    timeSinceStart: i64,
    rand: std.rand.DefaultPrng,
    fruitSpawnCountown: i64,
    bgEntity: ecs.Entity,
    bgUniforms: [2]zrender.Uniform,
    fgEntity: ecs.Entity,
    fgUniforms: [2]zrender.Uniform,
    // Cursor position in world space.
    cursorX: f32,
    cursorY: f32,
    lastCursorX: f32,
    lastCursorY: f32,
    // the frame time when the cursor was last updated
    lastCursorUpdate: i64,
    // Cursor speed in world space / second
    cursorVelX: f32,
    cursorVelY: f32,
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
