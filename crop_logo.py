from PIL import Image
import numpy as np

img = Image.open('assets/images/splash_logo.png').convert("RGBA")
data = np.array(img).astype(np.float32)

# Calculate perceived luminance
luminance = 0.299 * data[:,:,0] + 0.587 * data[:,:,1] + 0.114 * data[:,:,2]

# Create alpha mask: if luminance is less than 30, it's background -> alpha = 0
# Otherwise, we keep it fully opaque (255)
alpha = np.where(luminance < 30, 0, 255)
data[:,:,3] = alpha

img_transparent = Image.fromarray(data.astype(np.uint8))

# Now crop to bounding box
bbox = img_transparent.getbbox()
if bbox:
    img_transparent = img_transparent.crop(bbox)
    print("Cropped to:", bbox)
else:
    print("Could not find bounding box.")

img_transparent.save('assets/images/header_logo.png')
print("Saved header_logo.png with size:", img_transparent.size)
