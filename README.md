# GDS AI Policy Hub Prototype

## Introduction

This is a simple prototype to show how an AI Policy hub on GOV.UK might look & feel.

Right now it's made by capturing static HTML snapshots of various pages on on GOV.UK. 

There's probably a smarter way to do this via the [GOV.UK Prototype Toolkit](https://prototype-kit.service.gov.uk/docs/) but it's good enough for now.


## local development

Serve the pages by running `python3 -m http.server` then navigate to `http://[::]:8000` or `http://localhost:8000`

You can also use the helper script by running `sh ./dev.sh` or make the script executable by running `chmod +x run.sh` the first time. Then you can simply run `./dev.sh`

