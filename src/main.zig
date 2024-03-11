const std = @import("std");
const zengine = @import("zengine");
const zrender = @import("zrender");
// This is bad. This is so very bad.
// If you're a fellow jammer looking at this code for inspiration... don't.
// I don't know if even I understand how half of this insanity works.
// I thought my first and second ones had bad code... That was before I did this one.
const kinc = zrender.kinc;
const zlm = @import("zlm");
const ecs = @import("ecs");

// All spatial units are in screens per second.
// The viewport of the player is normalized so the smaller dimesion is 1, and the larger dimention is >=1.
const gravity = -2.0;

// The cursor trail knife thing is made of this many circles that are put together to look like a line.
// Also, updating and rendering 700 circles is literally like 80% of the games CPU usage lol
// 700 seemed like a good balance between performance and quality.
const numKnifeParts = 700;

const scoreScaleX = 0.025;
const scoreScaleY = scoreScaleX * 2;

// This is the primary balancing factor of the game: levels.

const Level = struct {
    // the length of this level in microseconds
    length: i64,
    // how many fruit of each type to spawn.
    fruits: []const FruitType,
    fruitNums: []const u32,
    abberation: zlm.Mat4,
};

const firstLevel = 0;

pub fn makeLevels() [14]Level {
    @setEvalBranchQuota(100000);
    return [_]Level{
        // 0: bunch of tomatos
        .{
            .length = 10 * std.time.us_per_s,
            .fruits = &[_]FruitType{.tomato},
            .fruitNums = &[_]u32{7},
            .abberation = zlm.Mat4.identity,
        },
        // 1: a single bomb
        .{
            .length = 3 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb},
            .fruitNums = &[_]u32{1},
            .abberation = zlm.Mat4.identity,
        },
        // 2: A mix of bombs and tomatos for the next minute
        .{
            .length = 60 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{5, 45},
            .abberation = zlm.Mat4.identity,
            
        },
        // 3: Now we start to introduce the abberation by scaling the knife movement a bit.
        // Players may or may not notice this because it's surprisingly subtle
        .{
            .length = 30 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{3, 23},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, 1.5, 1, 0),
        },
        // 4: A bit of rotation
        .{
            .length = 60 * std.time.us_per_s,
            .fruits = &[_]FruitType{.tomato},
            .fruitNums = &[_]u32{50},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, 1.5, 1, std.math.pi / 8.0),
        },
        // 5: add some more bombs
        .{
            .length = 30 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{5, 25},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, 1.5, 1, std.math.pi / 8.0),
        },
        // 6: make the rotation more extreme
        .{
            .length = 60 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{5, 50},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, 1.5, 1, std.math.pi / 4.0),
        },
        // 7: now for offset
        .{
            .length = 60 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{5, 50},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0.15, 0, 1.5, 1, std.math.pi / 4.0),
        },
        // 8: Change everything back to normal
        .{
            .length = 60 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{5, 50},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, 1, 1, 0),
        },
        // 9: invert X pos
        .{
            .length = 60 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{5, 50},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, -1, 1, 0),
        },
        // 10: invert X pos and rotate
        .{
            .length = 120 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{10, 100},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, -1, 1, std.math.pi / 8.0),
        },
        // 11: invert X pos and rotate 45 degrees
        .{
            .length = 120 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{10, 100},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, -1, 1, std.math.pi / 4.0),
        },
        // 11: invert X pos and rotate 90 degrees
        .{
            .length = 120 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{10, 100},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, -1, 1, std.math.pi / 2.0),
        },
        // This last level is really really really long and extremely dificult
        .{
            .length = 6000000 * std.time.us_per_s,
            .fruits = &[_]FruitType{.bomb, .tomato},
            .fruitNums = &[_]u32{5000000, 5000000},
            .abberation = AcerolaGameJamSystem.createAbberationTransform(0, 0, -1.5, 0.5, std.math.pi / 2.1),
        },
    };
}

// All of these comptime matrix muls cause a lot of branches so the compiler needs to be told to increase the limit
const levels = makeLevels();

// A component for a quad that stays in place in worldspace
const QuadComponent = struct {
    uniforms: [2]zrender.Uniform,
    x: f32,
    y: f32,
    angle: f32,
    scaleX: f32,
    scaleY: f32,
};

const GameState = enum {
    mainMenu,
    slice,
};

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

const KnifeData = struct {
    x: f32,
    y: f32,
    number: u32,
};

const FruitType = enum(u32) {
    tomato = 0,
    bomb,
    count,
};

const FruitComponent = struct {
    uniforms: [2] zrender.Uniform,
    fruit: Fruit,
    t: FruitType,
};

const CutFruitComponent = struct {
    uniforms: [2] zrender.Uniform,
    fruit: Fruit,
    t: FruitType,
    slice: u32,
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

const FruitTextureSet = struct {
    whole: zrender.TextureHandle,
    part1: zrender.TextureHandle,
    part2: zrender.TextureHandle,
};

// A "normal" ZEngine game should split functionality across many systems for better organization.
// This is a game jam so I don't give a crap.
const AcerolaGameJamSystem = struct {
    pub const name: []const u8 = "acerola_game_jam";
    pub const components = [_]type{FruitComponent, CutFruitComponent};
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
            .cursorX = 0,
            .cursorY = 0,
            .knifeX = 0,
            .knifeY = 0,
            .lastKnifeX = 0,
            .lastKnifeY = 0,
            .lastCursorUpdate = 0,
            .knifeVelX = 0,
            .knifeVelY = 0,
            .currentKnifeIndex = 0,
            .knifeData = [1]KnifeData{.{.number = numKnifeParts, .x = 0, .y = 0}} ** numKnifeParts,
            .knifeXLastUpdate = 0,
            .knifeYLastUpdate = 0,
            .score = 0,
            .scoreEntities = std.ArrayList(ecs.Entity).init(heapAllocator),
            .level = 0,
            .levelFruitNums = std.ArrayList(u32).init(heapAllocator),
            .levelFruitTypes = std.ArrayList(FruitType).init(heapAllocator),
            .mainMenuCooldown = 0,
            // these undefines are ok since they are set within SystemInit
            .quadMesh = undefined,
            .fruitTextures = undefined,
            .bgTexture = undefined,
            .fgTexture = undefined,
            .pipeline = undefined,
            .rand = undefined,
            .bgEntity = undefined,
            .bgUniforms = undefined,
            .fgEntity = undefined,
            .fgUniforms = undefined,
            .knifeTexture = undefined,
            .knifeEntities = undefined,
            .knifeUniforms = undefined,
            .gameState = undefined,
            .tutorial1Entity = undefined,
            .tutorial1Texture = undefined,
            .tutorial1Uniforms = undefined,
            .numberTextures = undefined,
            .levelFruitCooldownStart = undefined,
        };
    }

    pub fn systemInitGlobal(this: *@This(), registries: *zengine.RegistrySet, settings: anytype) !void {
        try this.initialSetup(registries);
        _ = settings;
    }

    fn clearEcs(this: *@This(), registries: *zengine.RegistrySet) !void {
        // this is an abomination
        registries.globalEcsRegistry.deinit();
        registries.globalEcsRegistry = ecs.Registry.init(this.allocator);
        this.scoreEntities.clearRetainingCapacity();
        try this.updateScoreDisplay(registries);
    }

    fn setupSlice(this: *@This(), registries: *zengine.RegistrySet) !void {
        try this.clearEcs(registries);
        this.gameState = .slice;
        this.score = 0;
        this.setLevel(firstLevel);
        // set up the bare ECS again (background, foreground, and the cursor trail)
        try this.setupEcs(registries);
        try this.updateScoreDisplay(registries);
        // TO make up for the fact that ZRender doesn't have this function,
        // Kinc is exposed so I can do dumb stuff like this
        kinc.kinc_mouse_lock(0);
    }

    fn updateScoreDisplay(this: *@This(), registries: *zengine.RegistrySet) !void {
        // clear out old entites
        for(this.scoreEntities.items) |entity| {
            registries.globalEcsRegistry.destroy(entity);
        }
        this.scoreEntities.clearRetainingCapacity();
        // "print" the score
        const scoreStr = try std.fmt.allocPrint(this.allocator, "{}", .{this.score});
        defer this.allocator.free(scoreStr);
        // create the quads for the numbers
        for(scoreStr, 0..) |character, index| {
            const texture = switch (character) {
                '0' => this.numberTextures[0],
                '1' => this.numberTextures[1],
                '2' => this.numberTextures[2],
                '3' => this.numberTextures[3],
                '4' => this.numberTextures[4],
                '5' => this.numberTextures[5],
                '6' => this.numberTextures[6],
                '7' => this.numberTextures[7],
                '8' => this.numberTextures[8],
                '9' => this.numberTextures[9],
                else => this.knifeTexture,
            };
            const quad = QuadComponent{
                .scaleX = scoreScaleX,
                .scaleY = scoreScaleY,
                // Hmm, a float cast. How odd.
                .x = 0.9 - scoreScaleX - scoreScaleX * @as(f32, @floatFromInt(index)) * 2.0,
                .y = 0.9 - scoreScaleY,
                .angle = 0,
                .uniforms = undefined,
            };
            const entity = this.spawnQuad(registries, quad, texture);
            try this.scoreEntities.append(entity);
        }
    }

    fn spawnQuad(this: *@This(), registries: *zengine.RegistrySet, quad: QuadComponent, texture: zrender.TextureHandle) ecs.Entity {
        const entity = registries.globalEcsRegistry.create();
        registries.globalEcsRegistry.add(entity, quad);
        const quadPtr = registries.globalEcsRegistry.get(QuadComponent, entity);
        registries.globalEcsRegistry.add(entity, zrender.RenderComponent {
            .mesh = this.quadMesh,
            .pipeline = this.pipeline,
            .uniforms = &quadPtr.uniforms,
        });
        var transform = getQuadTransform(quadPtr);
        const cameraTransform = getCameraTransform(registries.globalRegistry.getRegister(zrender.ZRenderSystem).?.getWindowResolution());
        transform = transform.mul(cameraTransform);
        quadPtr.uniforms[0] = .{.mat4 = zlmToZrenderMat4(transform)};
        quadPtr.uniforms[1] = .{.texture = texture};
        return entity;
    }

    fn setupEcs(this: *@This(), registries: *zengine.RegistrySet) !void {
        // yes, the cursor trail knife thing is essential
        for(0..this.knifeEntities.len) |i|{
            // knife entity
            this.knifeEntities[i] = registries.globalEcsRegistry.create();
            registries.globalEcsRegistry.add(this.knifeEntities[i], zrender.RenderComponent{
                .mesh = this.quadMesh,
                .pipeline = this.pipeline,
                .uniforms = &this.knifeUniforms[i],
            });

            this.knifeUniforms[i][0] = .{.mat4 = zrender.Mat4.identity};
            this.knifeUniforms[i][1] = .{.texture = this.knifeTexture};
        }

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
    }

    fn setupMainMenu(this: *@This(), registries: *zengine.RegistrySet) !void {
        try this.clearEcs(registries);
        this.gameState = .mainMenu;
        try this.setupEcs(registries);
        this.spawnFruit(registries, .tomato, Fruit{
            .angle = 0,
            .aVel = 0,
            .lastXPos = 0,
            .lastYPos = 0,
            .scale = 0.07,
            .xPos = 0,
            .yPos = 0,
            .xVel = 0,
            .yVel = 0, 
        });
        this.tutorial1Entity = registries.globalEcsRegistry.create();
        registries.globalEcsRegistry.add(this.tutorial1Entity, zrender.RenderComponent {
            .mesh = this.quadMesh,
            .pipeline = this.pipeline,
            .uniforms = &this.tutorial1Uniforms,
        });
        this.tutorial1Uniforms[0] = .{.mat4 = zrender.Mat4.identity};
        this.tutorial1Uniforms[1] = .{.texture = this.tutorial1Texture};
        this.mainMenuCooldown = 2 * std.time.us_per_s;
        this.setLevel(firstLevel);
        kinc.kinc_mouse_unlock();
    }

    fn initialSetup(this: *@This(), registries: *zengine.RegistrySet) !void {
        // Set up everything essential
        this.rand = std.rand.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
        const renderSystem = registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        renderSystem.updateDelta = std.time.us_per_s / 120;
        // create the pipeline
        this.pipeline = try renderSystem.createPipeline(@embedFile("shaderBin/shader.vert"), @embedFile("shaderBin/shader.frag"), .{
            .attributes = &Vertex.attributes,
            .uniforms = &[_]zrender.NamedUniformTag{ .{ .name = "transform", .tag = .mat4 }, .{ .name = "tex", .tag = .texture } },
        });
        // Load assets
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

        const bombTexture = try renderSystem.loadTexture(@embedFile("assets/bomb.png"));

        this.fruitTextures = [@intFromEnum(FruitType.count)]FruitTextureSet{
            .{
                .whole = try renderSystem.loadTexture(@embedFile("assets/tomato.png")),
                .part1 = try renderSystem.loadTexture(@embedFile("assets/tomato1.png")),
                .part2 = try renderSystem.loadTexture(@embedFile("assets/tomato2.png")),
            },
            .{
                .whole = bombTexture,
                .part1 = bombTexture,
                .part2 = bombTexture,
            }
        };
        this.bgTexture = try renderSystem.loadTexture(@embedFile("assets/bg.png"));
        this.fgTexture = try renderSystem.loadTexture(@embedFile("assets/fg.png"));
        this.knifeTexture = try renderSystem.loadTexture(@embedFile("assets/knife.png"));
        this.tutorial1Texture = try renderSystem.loadTexture(@embedFile("assets/tutorial1.png"));

        this.numberTextures = [10]zrender.TextureHandle{
            try renderSystem.loadTexture(@embedFile("assets/0.png")),
            try renderSystem.loadTexture(@embedFile("assets/1.png")),
            try renderSystem.loadTexture(@embedFile("assets/2.png")),
            try renderSystem.loadTexture(@embedFile("assets/3.png")),
            try renderSystem.loadTexture(@embedFile("assets/4.png")),
            try renderSystem.loadTexture(@embedFile("assets/5.png")),
            try renderSystem.loadTexture(@embedFile("assets/6.png")),
            try renderSystem.loadTexture(@embedFile("assets/7.png")),
            try renderSystem.loadTexture(@embedFile("assets/8.png")),
            try renderSystem.loadTexture(@embedFile("assets/9.png")),
        };

        try this.setupMainMenu(registries);

        renderSystem.onFrame.sink().connectBound(this, "onFrame");
        renderSystem.onUpdate.sink().connectBound(this, "onUpdate");
        renderSystem.onMousePress.sink().connectBound(this, "onClick");
        renderSystem.onMouseMove.sink().connectBound(this, "onMouseMove");
    }

    fn spawnFruit(this: *@This(), registries: *zengine.RegistrySet, t: FruitType, fruit: Fruit) void {
        const textures = this.fruitTextures[@intFromEnum(t)];
        const entity = registries.globalEcsRegistry.create();
        registries.globalEcsRegistry.add(entity, FruitComponent {
            .uniforms = [_]zrender.Uniform{.{.mat4 = zrender.Mat4.identity}, .{.texture = textures.whole}},
            .fruit = fruit,
            .t = t,
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
        const renderSystem = args.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        const cameraTransform = getCameraTransform(renderSystem.getWindowResolution());
        this.updateKnifePos(args.time, args.registries);
        switch (this.gameState) {
            .slice => onSliceFrame(this, args, cameraTransform),
            .mainMenu => onMainMenuFrame(this, args),
        }
        // Things that happen no matter the game state
        // update foreground and background transforms
        var bgTransform = zlm.Mat4.createTranslationXYZ(0, 0, 0.75);
        this.bgUniforms[0].mat4 = zlmToZrenderMat4(bgTransform.mul(cameraTransform));
        var fgTransform = zlm.Mat4.createTranslationXYZ(0, 0, 1.1);
        fgTransform = zlm.Mat4.createUniformScale(3).mul(fgTransform);
        this.fgUniforms[0].mat4 = zlmToZrenderMat4(fgTransform.mul(cameraTransform));
    }

    fn onMainMenuFrame(this: *@This(), args: zrender.OnFrameEventArgs) void {
        var switchToNext = false;
        const renderSystem = args.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        const cameraTransform = getCameraTransform(renderSystem.getWindowResolution());
        // update fruit without moving them
        const view = args.registries.globalEcsRegistry.basicView(FruitComponent);
        var iterator = view.entityIterator();
        var fruitToRemove = std.ArrayList(ecs.Entity).init(this.allocator);
        defer fruitToRemove.deinit();
        var cutFruitToSpawn = std.ArrayList(FruitComponent).init(this.allocator);
        defer cutFruitToSpawn.deinit();
        while(iterator.next()) |entity| {
            // explicit type hint because zls isn't very good at comptime stuff
            const fruit: *FruitComponent = view.get(entity);
            // delete fruit that fall offscreen
            if(fruit.fruit.yPos < -1.5) {
                fruitToRemove.append(entity) catch @panic("Out of memory!");
                continue;
            }
            const renderComponent = args.registries.globalEcsRegistry.get(zrender.RenderComponent, entity);

            // If the fruit is near the cursor and the cursor is moving greater than a certain speed,
            // then that fruit gets deleted
            const fruitCursorDistance = segmentSegmentDistance(this.knifeX, this.knifeY, this.lastKnifeX, this.lastKnifeY, fruit.fruit.xPos, fruit.fruit.yPos, fruit.fruit.lastXPos, fruit.fruit.lastYPos);
            const cursorVelocity = this.knifeVelX * this.knifeVelX + this.knifeVelY * this.knifeVelY;
            if(this.mainMenuCooldown < 0 and fruitCursorDistance < fruit.fruit.scale and cursorVelocity > 0.6) {
                cutFruitToSpawn.append(fruit.*) catch @panic("Out of memory!");
                fruitToRemove.append(entity) catch @panic("Out of memory!");
                // switch to next scene
                switchToNext = true;
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
        // Switching scene before spawning slices is not the best way to make the slices persist from the main menu into slice but it works so who cares anyway
        if(switchToNext){
            this.setupSlice(args.registries) catch @panic("failed to switch to slice scene");
        }
        for(cutFruitToSpawn.items) |*fruit| {
            this.spawnFruitSlice(&args.registries.globalEcsRegistry, fruit, 1);
            this.spawnFruitSlice(&args.registries.globalEcsRegistry, fruit, 2);
        }
        // The fruit was already deleted from the screen change
        // for(fruitToRemove.items) |entity| {
        //     args.registries.globalEcsRegistry.destroy(entity);
        // }
        // Update the tutorial thingies transform
        {
            var transform = zlm.Mat4.createScale(-0.5, 0.25, 1);
            transform = transform.mul(zlm.Mat4.createTranslationXYZ(0, 0.3, 1.0));
            this.tutorial1Uniforms[0].mat4 = zlmToZrenderMat4(transform.mul(cameraTransform));
        }
        this.mainMenuCooldown -= args.delta;
    }

    fn onSliceFrame(this: *@This(), args: zrender.OnFrameEventArgs, cameraTransform: zlm.Mat4) void {
        this.fruitSpawnCountown -= args.delta;
        var random = this.rand.random();
        // Every time @as(@floatFromInt) is needed, I am reminding you how silly this is
        const deltaSeconds: f32 = @as(f32, @floatFromInt(args.delta)) / std.time.us_per_s;

        if(this.fruitSpawnCountown < 0) {
            //total the number of fruit
            var fruitLeftInLevel: u32 = 0;
            for(this.levelFruitNums.items) |num| {
                fruitLeftInLevel += num;
            }
            var randomFruit = random.intRangeLessThan(u32, 0, fruitLeftInLevel);
            var foundFruitIndex = false;
            var randomFruitIndex: usize = 0;
            // figure out what actual fruit type that fruit corresponts to
            for(0..this.levelFruitNums.items.len) |i| {
                // see if this is the index our fruit is in
                if(this.levelFruitNums.items[i] >= randomFruit){
                    randomFruitIndex = i;
                    foundFruitIndex = true;
                    break;
                }
                // If it isn't, continue
                randomFruit -= this.levelFruitNums.items[i];
            }
            if(!foundFruitIndex) @panic("oh no!");
            this.levelFruitNums.items[randomFruitIndex] -= 1;
            const newFruitXPos = random.float(f32) * 1.5 - (1.5 / 2.0);
            const newFruitYPos = -1.0;
            const newFruitXTarget = random.float(f32) * 1.2 - (1.2 / 2.0);
            // Decreasing this value will make the fruit tend towards the edge while increasing it will make fruit tend towards the top.
            const newFruitYTarget = 1.0;
            const newFruitVelocity = 2.5;
            // Make a vector that points from newFruitPos to newFruitTarget that has a magnitude of newFruitVelocity
            var newfruitXVelocity: f32 = newFruitXTarget - newFruitXPos;
            var newfruitYVelocity: f32 = newFruitYTarget - newFruitYPos;
            const newFruitVelocityMagnitude = @sqrt(newfruitXVelocity * newfruitXVelocity + newfruitYVelocity * newfruitYVelocity);
            newfruitXVelocity *= newFruitVelocity / newFruitVelocityMagnitude;
            newfruitYVelocity *= newFruitVelocity / newFruitVelocityMagnitude;
            this.spawnFruit(args.registries, this.levelFruitTypes.items[randomFruitIndex], Fruit {
                .angle = 0,
                .aVel = random.float(f32) * 3.0 - (3.0 / 2.0),
                .scale = 0.07,
                .xPos = newFruitXPos,
                .yPos = newFruitYPos,
                // These are only used for detecting when the fruit is cut so it doesn't really matter what these are
                .lastXPos = newFruitXPos,
                .lastYPos = newFruitXPos,
                .xVel = newfruitXVelocity,
                .yVel = newfruitYVelocity,
            });
            std.debug.print("Level {} Spawned a {}, there are {} left.\n", .{this.level, this.levelFruitTypes.items[randomFruitIndex], this.levelFruitNums.items[randomFruitIndex]});
            // If this fruit type ran out, remove it
            if(this.levelFruitNums.items[randomFruitIndex] == 0) {
                _ = this.levelFruitTypes.swapRemove(randomFruitIndex);
                _ = this.levelFruitNums.swapRemove(randomFruitIndex);
            }
            // Add the first half of the cooldown before the level change.
            // do it in halves so that level changes are less sudden.
            // Specifically level 1 is very different from 0 and 2, which is a bit of a shock when it takes forever from level 0 and level 2 begins immediately after level 1 ends
            this.fruitSpawnCountown += @divTrunc(this.levelFruitCooldownStart, 2);
            // If there are no fruit left, go to the next level
            if(fruitLeftInLevel <= 1) {
                this.setLevel(this.level+1);
            }
            // Add the second half of the cooldown after the level change
            this.fruitSpawnCountown += @divTrunc(this.levelFruitCooldownStart, 2);
        }
        this.updateFruit(args, deltaSeconds, cameraTransform);
        this.updateSlices(args, deltaSeconds, cameraTransform);
        this.updateQuads(args, cameraTransform);

    }

    fn setLevel(this: *@This(), level: usize) void {
        this.level = level;
        this.levelFruitNums.clearRetainingCapacity();
        this.levelFruitTypes.clearRetainingCapacity();
        for(levels[this.level].fruitNums) |v| {
            this.levelFruitNums.append(v) catch unreachable;
        }
        for(levels[this.level].fruits) |v| {
            this.levelFruitTypes.append(v) catch unreachable;
        }
        var fruitInNextLevel: u32 = 0;
        for(this.levelFruitNums.items) |num| {
            fruitInNextLevel += num;
        }
        this.levelFruitCooldownStart = @divTrunc(levels[this.level].length, fruitInNextLevel);
    }

    pub fn onUpdate(this: *@This(), args: zrender.OnUpdateEventArgs) void {
        // TODO: figure out why the knife pulsates so strangely
        const renderSystem = args.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        const cameraTransform = getCameraTransform(renderSystem.getWindowResolution());
        // Each knife has a certain degree of delay.
        // To achieve this delay, the oldest knife is updated to the to current mouse pos
        const knifeDotsPerUpdate = @divExact(numKnifeParts, 20);
        for(0..knifeDotsPerUpdate) |i| {
            // lerp the cursor position to create a line between where it was last update and where it is now
            // Also, mandatory note about Zig's silly float casting rules
            const w = @as(f32, @floatFromInt(i)) / knifeDotsPerUpdate;
            // lerp it backwards since this iterates away from the cursor.
            const knifeX = this.knifeX * (1 - w) + this.knifeXLastUpdate * w;
            const knifeY = this.knifeY * (1 - w) + this.knifeYLastUpdate * w;
            const currentKnifeData = &this.knifeData[this.currentKnifeIndex];
            currentKnifeData.number = @intCast(numKnifeParts - i);
            currentKnifeData.x = knifeX;
            currentKnifeData.y = knifeY;
            // increment
            this.currentKnifeIndex = @mod(this.currentKnifeIndex + 1, this.knifeUniforms.len);
        }
        // update the transforms of all of the knifes
        for(0..this.knifeEntities.len) |i|{
            // This is aboninably bad but whatever
            const data = &this.knifeData[i];
            // get the transform
            var knifeTransform = zlm.Mat4.createTranslationXYZ(data.x, data.y, 1.2);
            // Another silly float cast
            knifeTransform = zlm.Mat4.createUniformScale((@as(f32, @floatFromInt(data.number)) / numKnifeParts) * 0.01).mul(knifeTransform);
            this.knifeUniforms[this.currentKnifeIndex][0].mat4 = zlmToZrenderMat4(knifeTransform.mul(cameraTransform));
            // scale it down slightly
            knifeTransform = zlm.Mat4.createUniformScale(0.8).mul(knifeTransform);
            // re-apply the camera and update
            this.knifeUniforms[i][0].mat4 = zlmToZrenderMat4(knifeTransform.mul(cameraTransform));
            data.number = @intCast(std.math.clamp(@as(isize, data.number) - knifeDotsPerUpdate, 0, numKnifeParts));
        }
        this.knifeXLastUpdate = this.knifeX;
        this.knifeYLastUpdate = this.knifeY;
    }

    fn updateSlices(this: *@This(), args: zrender.OnFrameEventArgs, deltaSeconds: f32, cameraTransform: zlm.Mat4) void {
        const view = args.registries.globalEcsRegistry.basicView(CutFruitComponent);
        var iterator = view.entityIterator();
        var slicesToRemove = std.ArrayList(ecs.Entity).init(this.allocator);
        defer slicesToRemove.deinit();
        while(iterator.next()) |entity| {
            // explicit type hint because zls isn't very good at comptime stuff
            const fruit: *CutFruitComponent = view.get(entity);
            // delete slices that fall offscreen
            if(fruit.fruit.yPos < -1.5) {
                slicesToRemove.append(entity) catch @panic("Out of memory!");
            }
            // Update the slices
            fruit.fruit.yVel += gravity * deltaSeconds;
            fruit.fruit.lastXPos = fruit.fruit.xPos;
            fruit.fruit.lastYPos = fruit.fruit.yPos;
            fruit.fruit.yPos += fruit.fruit.yVel * deltaSeconds;
            fruit.fruit.xPos += fruit.fruit.xVel * deltaSeconds;
            fruit.fruit.angle += fruit.fruit.aVel * deltaSeconds;

            // Update the render component with the new data
            const renderComponent = args.registries.globalEcsRegistry.get(zrender.RenderComponent, entity);
            const objectTransform = getFruitTransform(fruit.fruit);
            const transform = objectTransform.mul(cameraTransform);
            // Sometimes, the renderComponent's reference to uniforms is invalidated when the ECS expands things,
            // So, set the render component to the correct one
            renderComponent.uniforms = &fruit.uniforms;
            renderComponent.uniforms[0] = .{ .mat4 = zlmToZrenderMat4(transform) };
        }
        for(slicesToRemove.items) |entity| {
            args.registries.globalEcsRegistry.destroy(entity);
        }
    }

    fn updateFruit(this: *@This(), args: zrender.OnFrameEventArgs, deltaSeconds: f32, cameraTransform: zlm.Mat4) void {
        const view = args.registries.globalEcsRegistry.basicView(FruitComponent);
        var iterator = view.entityIterator();
        var fruitToRemove = std.ArrayList(ecs.Entity).init(this.allocator);
        defer fruitToRemove.deinit();
        var cutFruitToSpawn = std.ArrayList(ecs.Entity).init(this.allocator);
        defer cutFruitToSpawn.deinit();
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

            // If the fruit is near the knife and the knife is moving greater than a certain speed,
            // then that fruit gets deleted
            const fruitKnifeDistance = segmentSegmentDistance(this.knifeX, this.knifeY, this.lastKnifeX, this.lastKnifeY, fruit.fruit.xPos, fruit.fruit.yPos, fruit.fruit.lastXPos, fruit.fruit.lastYPos);
            const knifeVelocity = this.knifeVelX * this.knifeVelX + this.knifeVelY * this.knifeVelY;
            if(fruitKnifeDistance < fruit.fruit.scale and knifeVelocity > 0.6) {
                cutFruitToSpawn.append(entity) catch @panic("Out of memory!");
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
        var switchToNextScene = false;
        for(cutFruitToSpawn.items) |entity| {
            const fruit = args.registries.globalEcsRegistry.get(FruitComponent, entity);
            this.spawnFruitSlice(&args.registries.globalEcsRegistry, fruit, 1);
            this.spawnFruitSlice(&args.registries.globalEcsRegistry, fruit, 2);
            switch (fruit.t) {
                .tomato => this.score += 100,
                // TODO: play some kind of explode animation
                .bomb => {
                    switchToNextScene = true;
                },
                .count => {},
            }
            this.updateScoreDisplay(args.registries) catch unreachable;
        }
        for(fruitToRemove.items) |entity| {
            args.registries.globalEcsRegistry.destroy(entity);
        }
        // Lol I don't know if this is the right panic function,
        // But I'm trying to avoid @Panic because it's not the recomended way to panic in Zig.
        if(switchToNextScene){
            this.setupMainMenu(args.registries) catch |err| std.builtin.panicUnwrapError(null, err);
        }
    }

    fn updateQuads(this: *@This(), args: zrender.OnFrameEventArgs, cameraTransform: zlm.Mat4) void {
        _ = this;
        const view = args.registries.globalEcsRegistry.basicView(QuadComponent);
        var iterator = view.entityIterator();
        while(iterator.next()) |entity| {
            // get the components
            const quad: *QuadComponent = args.registries.globalEcsRegistry.get(QuadComponent, entity);
            const render = args.registries.globalEcsRegistry.get(zrender.RenderComponent, entity);
            var transform = getQuadTransform(quad);
            transform = transform.mul(cameraTransform);
            quad.uniforms[0].mat4 = zlmToZrenderMat4(transform);
            render.uniforms = &quad.uniforms;
        }
    }

    fn getQuadTransform(quad: *QuadComponent) zlm.Mat4 {
        var transform = zlm.Mat4.createAngleAxis(zlm.Vec3.unitZ, quad.angle);
        transform = transform.mul(zlm.Mat4.createScale(-quad.scaleX, quad.scaleY, 1));
        transform = transform.mul(zlm.Mat4.createTranslationXYZ(quad.x, quad.y, 2));
        return transform;
    }

    fn spawnFruitSlice(this: *@This(), ecsRegistry: *ecs.Registry, fruit: *const FruitComponent, slice: u32) void {
        const entity = ecsRegistry.create();
        var fruitData = fruit.fruit;
        fruitData.xVel += this.knifeVelX * 0.1;
        fruitData.yVel += this.knifeVelY * 0.1;
        fruitData.xVel += this.rand.random().float(f32) * 2.0 - (2.0*0.5);
        ecsRegistry.add(entity, CutFruitComponent{
            .fruit = fruitData,
            .slice = slice,
            .t = fruit.t,
            .uniforms = fruit.uniforms,
        });
        const cut1Comp = ecsRegistry.get(CutFruitComponent, entity);
        ecsRegistry.add(entity, zrender.RenderComponent{
            .mesh = this.quadMesh,
            .pipeline = this.pipeline,
            .uniforms = &cut1Comp.uniforms,
        });
        if(slice == 1) {
            cut1Comp.uniforms[1] = .{.texture = this.fruitTextures[@intFromEnum(fruit.t)].part1};
        } else {
            cut1Comp.uniforms[1] = .{.texture = this.fruitTextures[@intFromEnum(fruit.t)].part2};
        }
        
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
        switch (this.gameState) {
            .mainMenu => {
            },
            .slice => {},
        }
    }

    pub fn onMouseMove(this: *@This(), args: zrender.OnMouseMoveEventArgs) void {
        // If the cursor is locked, integrate based on the deltas.
        if(kinc.kinc_mouse_is_locked()){
            this.cursorX += args.deltax;
            this.cursorY += args.deltay;
        } else {
            this.cursorX = args.x;
            this.cursorY = args.y;
        }
        this.lastCursorUpdate = args.time;
    }

    fn updateKnifePos(this: *@This(), time: i64, registries: *zengine.RegistrySet) void {
        const cursorDeltaTimeMicros: f32 = @floatFromInt(time - this.lastCursorUpdate);
        const cursorDeltaTime = cursorDeltaTimeMicros / std.time.us_per_s;
        const renderSystem = registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
        const resolution = renderSystem.getWindowResolution();
        const cameraMatrix = getCameraTransform(resolution);
        const inverseCameraMatrix = cameraMatrix.invert() orelse unreachable;

        var posInPixels = zlm.Vec4{.x = @floatFromInt(this.cursorX), .y = @floatFromInt(this.cursorY), .z = 0, .w = 1};
        const posInScreen = posInPixels.div(zlm.Vec4.new(@floatFromInt(resolution.width), @floatFromInt(resolution.height), 1, 1)).sub(zlm.Vec4.new(0.5, 0.5, 0, 0)).mul(zlm.Vec4.new(2, -2, 1, 1));
        const posInWorld = posInScreen.transform(inverseCameraMatrix).transform(levels[this.level].abberation);
        this.lastKnifeX = this.knifeX;
        this.lastKnifeY = this.knifeY;
        this.knifeX = posInWorld.x;
        this.knifeY = posInWorld.y;
        this.knifeVelX = (this.knifeX - this.lastKnifeX) / cursorDeltaTime;
        this.knifeVelY = (this.knifeY - this.lastKnifeY) / cursorDeltaTime;
    }

    pub fn systemDeinitGlobal(this: *@This(), registries: *zengine.RegistrySet) void {
        _ = registries;
        _ = this;
    }

    pub fn deinit(this: *@This()) void {
        this.scoreEntities.deinit();
        this.levelFruitNums.deinit();
        this.levelFruitTypes.deinit();
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
        return zlm.Mat4{ .fields = [_][4]f32{
            [_]f32{ m.m00, m.m10, m.m20, m.m30 },
            [_]f32{ m.m01, m.m11, m.m21, m.m31 },
            [_]f32{ m.m02, m.m12, m.m22, m.m32 },
            [_]f32{ m.m03, m.m13, m.m23, m.m33 },
        } };
    }

    fn createAbberationTransform(offsetX: f32, offsetY: f32, scaleX: f32, scaleY: f32, rotation: f32) zlm.Mat4 {
        var t = zlm.Mat4.identity;
        t = t.mul(zlm.Mat4.createTranslationXYZ(offsetX, offsetY, 0));
        t = t.mul(zlm.Mat4.createScale(scaleX, scaleY, 1));
        t = t.mul(zlm.Mat4.createAngleAxis(zlm.Vec3.unitZ, rotation));
        return t;
    }

    allocator: std.mem.Allocator,
    // If this wasn't a jam, I would write an actual asset manager instead of just plonking them here
    quadMesh: zrender.MeshHandle,
    fruitTextures: [@intFromEnum(FruitType.count)]FruitTextureSet,
    bgTexture: zrender.TextureHandle,
    fgTexture: zrender.TextureHandle,
    pipeline: zrender.PipelineHandle,
    knifeTexture: zrender.TextureHandle,
    tutorial1Texture: zrender.TextureHandle,
    timeSinceStart: i64,
    rand: std.rand.DefaultPrng,
    bgEntity: ecs.Entity,
    bgUniforms: [2]zrender.Uniform,
    fgEntity: ecs.Entity,
    fgUniforms: [2]zrender.Uniform,
    tutorial1Entity: ecs.Entity,
    tutorial1Uniforms: [2]zrender.Uniform,
    // cursor pos in pixel space
    cursorX: i32,
    cursorY: i32,
    // knife position in world space.
    knifeX: f32,
    knifeY: f32,
    // the knife position last frame
    // TODO: make sure onCursorMove is only called once per frame
    lastKnifeX: f32,
    lastKnifeY: f32,
    // This is used for the knife trail knife thingy
    knifeXLastUpdate: f32,
    knifeYLastUpdate: f32,
    // the frame time when the knife was last updated
    lastCursorUpdate: i64,
    // knife speed in world space / second
    knifeVelX: f32,
    knifeVelY: f32,
    // I'm supposed to use the ECS, and define the knifes behavior separately.
    // However this is a game jam so I don't really care.
    knifeEntities: [numKnifeParts]ecs.Entity,
    knifeUniforms: [numKnifeParts][2]zrender.Uniform,
    knifeData: [numKnifeParts]KnifeData,
    currentKnifeIndex: usize,
    gameState: GameState,
    score: u64,
    numberTextures: [10]zrender.TextureHandle,
    scoreEntities: std.ArrayList(ecs.Entity),
    // the current level
    level: usize,
    // how many fruit of each type to spawn.
    levelFruitTypes: std.ArrayList(FruitType),
    levelFruitNums: std.ArrayList(u32),
    // the amount of time between spawning fruit
    levelFruitCooldownStart: i64,
    // the amount of time left before spawning the next fruit
    fruitSpawnCountown: i64,
    // When hitting a bomb, it's too easy to immediately hit the fruit in the main menu and start the next game accidentally.
    // This cooldown avoids that.
    mainMenuCooldown: i64,
};

pub fn main() !void {
    var allocatorObj = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = allocatorObj.deinit();
    const allocator = allocatorObj.allocator();

    const ZEngine = zengine.ZEngine(.{
        .globalSystems = &[_]type{ zrender.ZRenderSystem, AcerolaGameJamSystem },
        .localSystems = &[_]type{},
    });
    var engine = try ZEngine.init(allocator, .{
        .zrender_title = "Fruit Oops"
    });
    defer engine.deinit();
    var zrenderSystem = engine.registries.globalRegistry.getRegister(zrender.ZRenderSystem).?;
    zrenderSystem.run();
}
