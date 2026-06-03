.PHONY: build check test clean release bump-patch bump-minor bump-major

VERSION := $(shell cat VERSION)

build:
	bash build.sh

check: build
	bash -n mac-optimizer.sh

test: build
	./mac-optimizer.sh --dry-run --yes

clean:
	rm -f mac-optimizer.sh

# Create and push a release tag — triggers the GitHub Actions release workflow
release: check
	@echo "Releasing v$(VERSION)..."
	git add -A
	git diff --cached --quiet || git commit -m "chore: release v$(VERSION)"
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin main "v$(VERSION)"
	@echo "Pushed v$(VERSION) — GitHub Actions will build and publish the release."

# Version bumpers — edit VERSION then commit
bump-patch:
	@IFS=. read -r maj min pat < VERSION; \
	echo "$$maj.$$min.$$((pat+1))" > VERSION; \
	git add VERSION; \
	git commit -m "chore: bump version to $$(cat VERSION)"

bump-minor:
	@IFS=. read -r maj min pat < VERSION; \
	echo "$$maj.$$((min+1)).0" > VERSION; \
	git add VERSION; \
	git commit -m "chore: bump version to $$(cat VERSION)"

bump-major:
	@IFS=. read -r maj min pat < VERSION; \
	echo "$$((maj+1)).0.0" > VERSION; \
	git add VERSION; \
	git commit -m "chore: bump version to $$(cat VERSION)"
