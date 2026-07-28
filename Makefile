.PHONY: test app clean

test:
	swift test

app:
	./Scripts/package_app.sh

clean:
	swift package clean
	rm -rf dist .build/app-package

