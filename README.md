# Leaf Error Middleware

[![Language](https://img.shields.io/badge/Swift-4-brightgreen.svg)](https://swift.org)
[![Build Status](https://travis-ci.org/brokenhandsio/leaf-error-middleware.svg?branch=master)](https://travis-ci.org/brokenhandsio/leaf-error-middleware)
[![Code Coverage](https://codecov.io/gh/brokenhandsio/leaf-error-middleware/branch/master/graph/badge.svg)](https://codecov.io/gh/brokenhandsio/leaf-error-middleware)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](https://raw.githubusercontent.com/brokenhandsio/leaf-error-middleware/master/LICENSE)

Leaf Error Middleware is a piece of middleware for [Vapor](https://github.com/vapor/vapor) which allows you to return custom 404 and server error pages. It supports both Swift 3 and Swift 4.

# Usage

To use the Leaf Error Middleware, just add the middleware to your `Config` and then to your `droplet.json` (make sure you `import LeafErrorMiddleware` at the top):

```swift
let config = Config()
config.addConfigurable(middleware: LeafErrorMiddleware.init, name: "leaf-error"))
let drop = Droplet(config)
```

This replaces the default error middleware in Vapor, so ***do not*** include the standard `error` in your `droplet.json`.

***Note:*** You should ensure you set the error middleware as the first middleware in your `droplet.json` to so all errors get caught (unless you are using something like [Vapor Security Headers](https://github.com/brokenhandsio/VaporSecurityHeaders/)):

```json
{
    ...
    "middleware": [
        "leaf-error",
        ...
    ],
    ...
}
```

You will need to add it as a dependency in your `Package.swift` file:

```swift
dependencies: [
    ...,
    .package(url: "https://github.com/brokenhandsio/VaporSecurityHeaders", from: "1.1.0")
]
```

# Setting Up

You need to include two [Leaf](https://github.com/vapor/leaf) templates in your application:

* `404.leaf`
* `serverError.leaf`

When Leaf Error Middleware catches a 404 error, it will return the `404.leaf` template. Any other error caught will return the `serverError.leaf` template.

The actual error will also be logged out to the `Droplet`s log.
