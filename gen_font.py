from PIL import Image, ImageDraw, ImageFont
import io, os

fontSize = 88
width = 48
height = 84

fnt = ImageFont.truetype('consola.ttf', fontSize)
charset = '�!"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~'

for idx, char in enumerate(charset):
	img = Image.new('RGB', (width, height), (0,0,0))
	d = ImageDraw.Draw(img)
	d.text((0, 0), char, font=fnt, fill=(255, 255, 255))

	img.save('frame_%d.bmp' % idx)
	
os.system('magick mogrify -gravity north -background black -extent %sx%s +flop *.bmp' % (width, height*2))