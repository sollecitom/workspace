#!/usr/bin/env just --justfile

resetAll:
    git fetch origin && git reset --hard origin/main && git clean -f -d

push:
    git diff --quiet HEAD || git commit -am "WIP" && git push origin main

pull:
    git pull

build:
    ./gradlew build

rebuild:
    ./gradlew --refresh-dependencies --rerun-tasks clean build

updateDependencies:
    ./gradlew versionCatalogUpdate

updateGradle:
    ./gradlew wrapper --gradle-version latest --distribution-type all

updateAll:
    just updateDependencies && just updateGradle

@update-workspace:
    just update-gradle-plugins
    just update-acme-schema-catalogue
    just update-swissknife
    just update-pillar
    just update-tools
    just update-examples
    just update-facts
    just update-backend-skeleton
    just update-modulith-example
    just update-element-service-example

@pull-workspace:
    just pull-gradle-plugins
    just pull-acme-schema-catalogue
    just pull-swissknife
    just pull-pillar
    just pull-tools
    just pull-examples
    just pull-facts
    just pull-backend-skeleton
    just pull-modulith-example
    just pull-element-service-example

@reset-workspace:
    just reset-gradle-plugins
    just reset-acme-schema-catalogue
    just reset-swissknife
    just reset-pillar
    just reset-tools
    just reset-examples
    just reset-facts
    just reset-backend-skeleton
    just reset-modulith-example
    just reset-element-service-example

@push-workspace:
    just push-gradle-plugins
    just push-acme-schema-catalogue
    just push-swissknife
    just push-pillar
    just push-tools
    just push-examples
    just push-facts
    just push-backend-skeleton
    just push-modulith-example
    just push-element-service-example

@build-workspace:
    just build-gradle-plugins
    just build-acme-schema-catalogue
    just build-swissknife
    just build-pillar
    just build-tools
    just build-examples
    just build-facts
    just build-backend-skeleton
    just build-modulith-example
    just build-element-service-example

[working-directory: 'gradle-plugins']
@update-gradle-plugins:
    pwd
    just pull
    just updateAll
    just build
    just publish

[working-directory: 'acme-schema-catalogue']
@update-acme-schema-catalogue:
    pwd
    just pull
    just updateAll
    just build
    just publish

[working-directory: 'swissknife']
@update-swissknife:
    pwd
    just pull
    just updateAll
    just build
    just publish

[working-directory: 'pillar']
@update-pillar:
    pwd
    just pull
    just updateAll
    just build
    just publish

[working-directory: 'tools']
@update-tools:
    pwd
    just pull
    just updateAll
    just build

[working-directory: 'examples']
@update-examples:
    pwd
    just pull
    just updateAll
    just build

[working-directory: 'facts']
@update-facts:
    pwd
    just pull
    just updateAll
    just build

[working-directory: 'modulith-example']
@update-modulith-example:
    pwd
    just pull
    just updateAll
    just build

[working-directory: 'element-service-example']
@update-element-service-example:
    pwd
    just pull
    just updateAll
    just build

[working-directory: 'gradle-plugins']
@build-gradle-plugins:
    pwd
    just build
    just publish

[working-directory: 'acme-schema-catalogue']
@build-acme-schema-catalogue:
    pwd
    just build
    just publish

[working-directory: 'swissknife']
@build-swissknife:
    pwd
    just build
    just publish

[working-directory: 'pillar']
@build-pillar:
    pwd
    just build
    just publish

[working-directory: 'tools']
@build-tools:
    pwd
    just build

[working-directory: 'examples']
@build-examples:
    pwd
    just build

[working-directory: 'facts']
@build-facts:
    pwd
    just build

[working-directory: 'modulith-example']
@build-modulith-example:
    pwd
    just build

[working-directory: 'element-service-example']
@build-element-service-example:
    pwd
    just build


[working-directory: 'gradle-plugins']
@pull-gradle-plugins:
    pwd
    just pull
    just build
    just publish

[working-directory: 'acme-schema-catalogue']
@pull-acme-schema-catalogue:
    pwd
    just pull
    just build
    just publish

[working-directory: 'swissknife']
@pull-swissknife:
    pwd
    just pull
    just build
    just publish

[working-directory: 'pillar']
@pull-pillar:
    pwd
    just pull
    just build
    just publish

[working-directory: 'tools']
@pull-tools:
    pwd
    just pull
    just build

[working-directory: 'examples']
@pull-examples:
    pwd
    just pull
    just build

[working-directory: 'facts']
@pull-facts:
    pwd
    just pull
    just build

[working-directory: 'modulith-example']
@pull-modulith-example:
    pwd
    just pull
    just build

[working-directory: 'element-service-example']
@pull-element-service-example:
    pwd
    just pull
    just build

[working-directory: 'gradle-plugins']
@push-gradle-plugins:
    pwd
    just push

[working-directory: 'acme-schema-catalogue']
@push-acme-schema-catalogue:
    pwd
    just push

[working-directory: 'swissknife']
@push-swissknife:
    pwd
    just push

[working-directory: 'pillar']
@push-pillar:
    pwd
    just push

[working-directory: 'tools']
@push-tools:
    pwd
    just push

[working-directory: 'examples']
@push-examples:
    pwd
    just push

[working-directory: 'facts']
@push-facts:
    pwd
    just push

[working-directory: 'modulith-example']
@push-modulith-example:
    pwd
    just push

[working-directory: 'element-service-example']
@push-element-service-example:
    pwd
    just push


[working-directory: 'gradle-plugins']
@reset-gradle-plugins:
    pwd
    git clean -fdx & git reset --hard
    just build
    just publish

[working-directory: 'acme-schema-catalogue']
@reset-acme-schema-catalogue:
    pwd
    git clean -fdx & git reset --hard
    just build
    just publish

[working-directory: 'swissknife']
@reset-swissknife:
    pwd
    git clean -fdx & git reset --hard
    just build
    just publish

[working-directory: 'pillar']
@reset-pillar:
    pwd
    git clean -fdx & git reset --hard
    just build
    just publish

[working-directory: 'tools']
@reset-tools:
    pwd
    git clean -fdx & git reset --hard
    just build

[working-directory: 'examples']
@reset-examples:
    pwd
    git clean -fdx & git reset --hard
    just build

[working-directory: 'facts']
@reset-facts:
    pwd
    git clean -fdx & git reset --hard
    just build

[working-directory: 'modulith-example']
@reset-modulith-example:
    pwd
    git clean -fdx & git reset --hard
    just build

[working-directory: 'element-service-example']
@reset-element-service-example:
    pwd
    git clean -fdx & git reset --hard
    just build

[working-directory: 'backend-skeleton']
@update-backend-skeleton:
    pwd
    just pull
    just update-all
    just build

[working-directory: 'backend-skeleton']
@build-backend-skeleton:
    pwd
    just build

[working-directory: 'backend-skeleton']
@pull-backend-skeleton:
    pwd
    just pull
    just build

[working-directory: 'backend-skeleton']
@push-backend-skeleton:
    pwd
    just push

[working-directory: 'backend-skeleton']
@reset-backend-skeleton:
    pwd
    git clean -fdx & git reset --hard
    just build

@reinstall-workspace:
    pwd
    rm -rf ./gradle-plugins
    git clone git@github.com:sollecitom/gradle-plugins.git
    just build-gradle-plugins

    pwd
    rm -rf ./acme-schema-catalogue
    git clone git@github.com:sollecitom/acme-schema-catalogue.git
    just build-acme-schema-catalogue

    pwd
    rm -rf ./swissknife
    git clone git@github.com:sollecitom/swissknife.git
    just build-swissknife

    pwd
    rm -rf ./pillar
    git clone git@github.com:sollecitom/pillar.git
    just build-pillar

    pwd
    rm -rf ./tools
    git clone git@github.com:sollecitom/tools.git
    just build-tools

    pwd
    rm -rf ./examples
    git clone git@github.com:sollecitom/examples.git
    just build-examples

    pwd
    rm -rf ./facts
    git clone git@github.com:sollecitom/facts.git
    just build-facts

    pwd
    rm -rf ./backend-skeleton
    git clone git@github.com:sollecitom/backend-skeleton.git
    just build-backend-skeleton

    pwd
    rm -rf ./modulith-example
    git clone git@github.com:sollecitom/modulith-example.git
    just build-modulith-example

    pwd
    rm -rf ./element-service-example
    git clone git@github.com:sollecitom/element-service-example.git
    just build-element-service-example