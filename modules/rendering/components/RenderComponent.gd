## RenderComponent.gd
## Stores the visual representation of an entity for the ASCII renderer.
## Systems write here; AsciiRenderSystem reads here every frame.
class_name RenderComponent
extends Resource

## Single ASCII character to display.
var glyph: String = "?"

## Foreground (text) color.
var fg_color: Color = Color.WHITE

## Background (cell fill) color.
var bg_color: Color = Color.BLACK

## Reserved for layered rendering (e.g. items on top of terrain).
## Higher values render on top. Not yet used by AsciiRenderSystem.
var z_layer: int = 0
