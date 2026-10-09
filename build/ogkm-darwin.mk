# Included after NVIDIA's src/nvidia or src/nvidia-modeset Makefile.
# Compile the upstream OS-independent sources with Apple clang, but deliberately
# skip NVIDIA's ELF/GNU-ld final link.  The caller supplies DARWIN_ARCHIVE.

.PHONY: darwin-archive
darwin-archive: $(filter-out $(SHADER_OBJS),$(OBJS))
	@test -n "$(DARWIN_ARCHIVE)" || { echo "DARWIN_ARCHIVE is required" >&2; exit 2; }
	@mkdir -p "$(dir $(DARWIN_ARCHIVE))"
	/usr/bin/libtool -static -o "$(DARWIN_ARCHIVE)" $^

