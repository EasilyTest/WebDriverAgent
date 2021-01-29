# Contributing to WebDriverAgent
We want to make contributing to this project as easy and transparent as
possible.

## Pull Requests
We actively welcome your pull requests.

1. Fork the repo and create your branch from `master`.
2. If you've added code that should be tested, add tests
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes.
5. Make sure your code lints.
6. If you haven't already, complete the Contributor License Agreement ("CLA").

## Contributor License Agreement ("CLA")
In order to accept your pull request, we need you to submit a CLA. You only need
to do this once to work on any of Facebook's open source projects.

Complete your CLA here: <https://code.facebook.com/cla>

## Issues
We use GitHub issues to track public bugs. Please ensure your description is
clear and has sufficient instructions to be able to reproduce the issue.

Facebook has a [bounty program](https://www.facebook.com/whitehat/) for the safe
disclosure of security bugs. In those cases, please go through the process
outlined on that page and do not file a public issue.

## Coding Style
* 2 spaces for indentation rather than tabs
* 80 character line length

## Update Carthage Dependencies

1. Add a new version tag to the target repository
    - e.g. https://github.com/appium/RoutingHTTPServer/releases
    - Please ask developers who have a permission to add the tag on the target repository
      - The appium or appium forked repositories are Appium team members
2. Bump the version in `Cartfile.resolved`
    - Please make sure the version will be downloaded and built by `carthage bootstrap` command like below
        ```
        $ carthage bootstrap # in appium/WebDriverAgent directory
        *** Checking out RoutingHTTPServer at "v1.2.0"
        *** Checking out CocoaAsyncSocket at "7.6.3"
        *** Checking out YYCache at "1.1.0"
        ```
3. Create a PR to appium/WebDriverAgent repository to apply the update

## License
By contributing to WebDriverAgent, you agree that your contributions will be licensed
under its [BSD license](LICENSE).
