# Changelog

## [0.4.0](https://github.com/JuanVqz/jekyll-devto/compare/v0.3.1...v0.4.0) (2026-10-05)


### Features

* **publisher:** publish an imported archive a few posts at a time ([#18](https://github.com/JuanVqz/jekyll-devto/issues/18)) ([981045b](https://github.com/JuanVqz/jekyll-devto/commit/981045b9ad702c586a5cb6672b1981d7e4958257))

## [0.3.1](https://github.com/JuanVqz/jekyll-devto/compare/v0.3.0...v0.3.1) (2026-10-02)


### Bug Fixes

* **feed:** ignore front matter values of the wrong type instead of crashing ([#16](https://github.com/JuanVqz/jekyll-devto/issues/16)) ([a890385](https://github.com/JuanVqz/jekyll-devto/commit/a890385ad4427fb2875f78e723d4f750eadcfb6b))

## [0.3.0](https://github.com/JuanVqz/jekyll-devto/compare/v0.2.0...v0.3.0) (2026-10-02)


### ⚠ BREAKING CHANGES

* **feed:** posts no longer get their image as the dev.to cover by default. Set devto: { cover: image } in _config.yml to keep the 0.2.0 behavior.

### Features

* **feed:** add a dev.to cover only when asked for ([#14](https://github.com/JuanVqz/jekyll-devto/issues/14)) ([9e9b43f](https://github.com/JuanVqz/jekyll-devto/commit/9e9b43f9422cee3ef4fd7a47aa483347bf5bfde8))

## [0.2.0](https://github.com/JuanVqz/jekyll-devto/compare/v0.1.0...v0.2.0) (2026-10-02)


### Features

* choose dev.to tags and series from the post's front matter ([#13](https://github.com/JuanVqz/jekyll-devto/issues/13)) ([1aa48f7](https://github.com/JuanVqz/jekyll-devto/commit/1aa48f7a362781f660a54d6e041f043db5a11eb8))
* **html:** bring code block languages to dev.to ([#11](https://github.com/JuanVqz/jekyll-devto/issues/11)) ([2e62edb](https://github.com/JuanVqz/jekyll-devto/commit/2e62edb47809cc945af3988973e6c44ad9fe2a27))
* **publisher:** use the post image as the dev.to cover ([#12](https://github.com/JuanVqz/jekyll-devto/issues/12)) ([90707e7](https://github.com/JuanVqz/jekyll-devto/commit/90707e71fbaa5d309bed29ddc455c04bea07237d))


### Documentation

* add gem version and CI badges to the README ([#8](https://github.com/JuanVqz/jekyll-devto/issues/8)) ([a0d2a9c](https://github.com/JuanVqz/jekyll-devto/commit/a0d2a9c47a871597bd4d3f4c1ac113c18b41a323))

## 0.1.0 (2026-10-01)


### Features

* add jekyll-devto to cross-post a Jekyll blog to dev.to ([b9b0356](https://github.com/JuanVqz/jekyll-devto/commit/b9b0356ddf7bb767670140195dc3e0991fd4ba84))
