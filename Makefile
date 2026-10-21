# Command Line Tools ship swift-testing outside the default search paths.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(if $(wildcard $(CLT_DEV)/Frameworks/Testing.framework),\
	-Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib)

.PHONY: app run install test preview icon clean

app:
	./scripts/bundle.sh

run: app
	pkill -x Clipster || true
	open build/Clipster.app

install: app
	pkill -x Clipster || true
	rm -rf /Applications/Clipster.app
	cp -R build/Clipster.app /Applications/
	open /Applications/Clipster.app

test:
	swift test $(TEST_FLAGS)

# Shows the panel centered with sample data (in-memory, nothing saved).
preview:
	swift run Clipster --preview

# Re-render Resources/AppIcon.icns after editing scripts/make-icon.swift.
icon:
	./scripts/make-icon.sh

clean:
	rm -rf .build build
