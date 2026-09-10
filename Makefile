.PHONY: build debug run install test logs clean

build:
	bash scripts/build-app.sh release

debug:
	bash scripts/build-app.sh debug

run: build
	bash scripts/run-app.sh

install: build
	ditto build/AIUsage.app /Applications/AIUsage.app
	bash scripts/run-app.sh /Applications/AIUsage.app

test:
	bash scripts/test.sh

logs:
	log stream --predicate 'subsystem == "dev.krupanjac.AIUsage"' --level info

clean:
	swift package clean
	rm -rf build
