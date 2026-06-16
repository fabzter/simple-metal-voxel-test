# 1. Compile with aggressive optimization (-O) for Apple Silicon
swiftc -O -o VoxelGame voxel_game.swift -framework Cocoa -framework Metal -framework CoreGraphics

# 2. Run the game
./VoxelGame
