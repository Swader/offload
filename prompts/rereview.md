Re review this implementation from an extremely adversarial perspective using the be-thorough skill. Always keep in mind blast radius and collateral damage - as you touch files, what other services use them? What footguns are we firing, what trapdoors are we laying down? What could bite us in the ass later because we haven’t had 2nd, 3rd, or 10th order effects in mind? Comb through it using subagents of different personas, always skeptical about the implementation and eager to find issues that are genuinely blocking, not nits for nits’ sake.

If this is already a PR, check also PR comments and reviews by humans or PR bots for anything actionable. If CI is red try to make it green if the redness comes from this PR’s code.

If you run into any findings, fix and then re-run loop until no actionable findings remain.
