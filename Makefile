MKDIRS   = mkdir -vp FreeBSD/meta FreeBSD/stage Debian/DEBIAN; cp -vp ../make-pkg.conf.sample make-pkg.conf

PKG_MAKE = PATH=~git/bin:$(PATH) make-pkg.sh
PKG_MOVE = PATH=~git/bin:$(PATH) move-pkgs.sh

pkg:
	$(PKG_MAKE)

move:
	$(PKG_MOVE)

empty:
	$(MKDIRS)
	
