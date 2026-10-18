(meta
  (tag "blog" "photos")
  (published "2026-01-17")
  (modified "2026-09-22")
  (author "Emile")
  (info "tag" "published")
)

# Photo Orga

(toc)

So I've come to the point where I've got anough images so that I should think a bit more about how I organise them.

## The old process

Take picture (Phone, Mirrorless, Screenshot) -> Import into Apple Photos on the Macbook.

Now the photo library got big, about 30000 photos (and some videos) which took up about 500GB of space.

## New Process

1. Take Photos (Phone, Mirrorless, Screenshot)
2. Import into Photos
3. Once a Month, export Originals to Folder (`~/Desktop/2025-11`)
4. Tar Folder (`cd ~/Desktop/2025-11 && tar -cvf 2025-11.tar *`)
5. Copy tar to **NAS** (`/data/private/Photos/2025/2025-11`) (drag and drop via SMB on the local network, that way I can max out the gigabit connection)
6. On the NAS, extract the tar (`time tar -xvf 2025-11.tar`)
7. Rsync the Photos folder to the grave (`cd /data/private/Photos && rsync -arzv * medano:/grave/photos`)
8. Import the images to the photo library of the year (Open Photos while holding the option key from the "five finger pinch menu")
  * (I've currently got a photo library for each year, but am thinking of just creating one and importing all the images into that one)

Now for viewing the photos on the NAS, I've got two options:

### Immich

Immich can use the filesystem as a backend for accessing the photos and can thus be used to view old picture I don't want to store on my laptop / phone

### Photo library via SMB

Apple Photos can work with multiple photo libraries (although not great...)

When opening photos via the "five finger pinch application menu", hold the option key, Photos then allows choosing an external library, which can reside on the Nas.

