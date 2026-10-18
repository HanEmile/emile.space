(meta
  (tag "project" "jufo")
  (published "2019-01-01")
  (modified "2026-09-22")
  (author "Emile")
  (info "tag")
)

# Galaxy Simulation (2019)

After having generated multiple galaxies, I realized that it would be fun to do stuff with the stars.

![](/jufo-galaxy-simulation-example_image_cropped.png)

The image above shows two heavy masses in a field of stars. The direction of the force acting on the stars is dispalyed using the line pointing away from the individual star. The intensity of the force acting is depicted using colors (blue=low force, red=higher force).

If you find this interesting and want to read a comprehensive introduction on how this works, you can read the [Paged Out!](/paged-out) article I wrote about this.

- [https://git.darknebu.la/GalaxySimulator](https://git.darknebu.la/GalaxySimulator)
- [langfassung](/jufo-galaxy-simulation-langfassung.pdf) (pdf, 292 KB)
- [posters](/jufo-galaxy-simulation-posters.pdf) (pdf, 1.3 MB)
- [series](/jufo-galaxy-simulation-series.pdf) (pdf, 409 KB)
- [tree](/jufo-galaxy-simulation-tree.pdf) (pdf, 45 KB)

## quadtree

The below quadtree contains a single star in each cell:

### 50 stars

![](/jufo-galaxy-simulation-barnes-hut-tree-50-negated.png)
[high-res dark version](/jufo-galaxy-simulation-barnes-hut-tree-50.png)

### 1000 stars

![](/jufo-galaxy-simulation-barnes-hut-tree-1000-negated.png)
[high-res dark version](/jufo-galaxy-simulation-barnes-hut-tree-1000.png)

