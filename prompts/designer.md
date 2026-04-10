turn this into an agent under /agents, use your skill.
structured input and output.


The Practical UI/UX Design Workflow
1. Discovery & Research (before pixels)
Start with the problem, not the screen. Talk to 5–8 real users, watch them struggle with the current solution, and write down their exact words. Define: who is this for, what job are they hiring your product to do (Jobs-to-be-Done framework), and what does success look like measurably. Output: a one-page brief with user, problem, goal, and constraints.
2. Information Architecture
Map the content and flows before styling anything. Use card sorting for navigation, then sketch user flows (Figma, paper, whatever) showing every state: empty, loading, error, success, edge cases. Most junior designers skip states — principals obsess over them.
3. Low-fi Wireframes
Grayscale boxes only. This forces focus on hierarchy, layout, and flow instead of colors and shadows. Iterate fast, throw away freely.
4. Visual Design System First, Screens Second
Build tokens before screens: typography scale (modular, e.g. 1.25 ratio), spacing scale (4 or 8px base), color system (semantic: bg-primary, text-muted, not blue-500), radii, shadows, motion curves. Then components. Then screens compose from components. This is how you get consistency at scale.
5. Prototype & Test
Clickable Figma prototype → test with 5 users (Nielsen: 5 users catch ~85% of issues). Watch silently. Iterate.
Core Laws & Principles to Internalize
	∙	Hick’s Law — more choices = slower decisions. Reduce options.
	∙	Fitts’s Law — targets should be large and close. Primary actions get bigger buttons.
	∙	Miller’s Law — chunk information into groups of 5–9.
	∙	Jakob’s Law — users expect your app to work like others they know. Don’t reinvent common patterns.
	∙	Gestalt principles — proximity, similarity, continuity drive visual grouping.
	∙	Von Restorff effect — one thing stands out when it differs. Use for primary CTAs.
	∙	Progressive disclosure — show only what’s needed now.
	∙	Nielsen’s 10 heuristics — print them, tape them to your wall.
Craft-Level Guidelines
	∙	Typography carries 90% of the feel. Two fonts max, tight vertical rhythm, generous line-height (1.5–1.7 body).
	∙	Whitespace is a feature, not wasted space.
	∙	Contrast hierarchy: only 1 primary action per screen.
	∙	Accessibility is non-negotiable: WCAG AA minimum, 4.5:1 contrast, keyboard nav, focus states, semantic HTML.
	∙	Motion has meaning: 150–300ms, ease-out for entrances, ease-in for exits. Never decorative.
	∙	Design for the worst case first: long names, empty states, slow networks, errors.
Essential Literature
	∙	The Design of Everyday Things — Don Norman (mental models, affordances)
	∙	Don’t Make Me Think — Steve Krug (usability bible, 2 hour read)
	∙	Refactoring UI — Adam Wathan & Steve Schoger (most practical visual design book ever written — read this first if you read nothing else)
	∙	About Face — Alan Cooper (interaction design depth)
	∙	Laws of UX — Jon Yablonski (also a great free site: lawsofux.com)
	∙	Atomic Design — Brad Frost (free online, design systems thinking)
The Principal’s Mindset
Taste is built by volume + critique. Study 10 great products deeply (Linear, Arc, Raycast, Things, Stripe, Vercel) — screenshot flows, recreate them, understand why each decision was made. Keep a swipe file. Get your work critiqued weekly. Ship, measure, iterate — opinions without data are just aesthetics.
The shortcut: clarity > cleverness, always.