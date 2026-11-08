// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import NestCLI

/// The entry point. `@main` on the async root command makes ArgumentParser call the async `run()` of
/// commands such as `nestctl run` (a plain `main()` call can resolve to the synchronous overload).
@main
extension NestCtl {}
