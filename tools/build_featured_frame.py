"""Trace the generated gold frame into native Roblox GUI rectangles."""
import json
from pathlib import Path
from build_boss_titles import trace
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/ui/featured-shop'
data,preview=trace(OUT/'gold-frame.png',width=320)
preview.save(OUT/'gold-frame-trace.png')
(OUT/'gold-frame-trace.json').write_text(json.dumps(data,separators=(',',':')))
lines=['--!strict','-- Imagegen gold-frame.png traced with tools/build_boss_titles.py at 320 px.','return {',f'\tGrid = Vector2.new({data["Grid"][0]}, {data["Grid"][1]}),','\tPalette = {']
for color in data['Palette']:lines.append('\t\tColor3.fromRGB('+','.join(map(str,color))+'),')
lines += ['\t},','\tRects = {']
for x,y,w,h,key,_ in data['Rects']:lines.append('\t\t{'+','.join(map(str,[x,y,w,h,key%32+1]))+'},')
lines += ['\t},','}']
(ROOT/'src/shared/Config/FeaturedFrameTrace.luau').write_text('\n'.join(lines)+'\n')
print('Native frame rectangles:',len(data['Rects']))
