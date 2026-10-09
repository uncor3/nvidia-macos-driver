# Included after NVIDIA's src/nvidia or src/nvidia-modeset Makefile.
# Compile the upstream OS-independent sources with Apple clang, but deliberately
# skip NVIDIA's ELF/GNU-ld final link.  The caller supplies DARWIN_ARCHIVE.

# A combined kext may share a source implementation between the two archives.
# Exclude only explicitly requested objects, using NVIDIA's source-to-object map.
DARWIN_EXCLUDE_SRCS ?=
DARWIN_EXCLUDE_OBJS = $(call BUILD_OBJECT_LIST,$(DARWIN_EXCLUDE_SRCS))

.PHONY: darwin-archive
darwin-archive: $(filter-out $(SHADER_OBJS) $(DARWIN_EXCLUDE_OBJS),$(OBJS))
	@test -n "$(DARWIN_ARCHIVE)" || { echo "DARWIN_ARCHIVE is required" >&2; exit 2; }
	@mkdir -p "$(dir $(DARWIN_ARCHIVE))"
	/usr/bin/libtool -static -o "$(DARWIN_ARCHIVE)" $^

