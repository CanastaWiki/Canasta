Canasta version history:

- 1.0.0 - April 14, 2022 - initial version
- 1.0.1 - April 14, 2022 - update MediaWiki version to 1.35.6
- 1.1.0 - April 29, 2022 - rename /user-extensions and /user-skins directories to /extensions and /skins
- 1.1.1 - June 16, 2022 - Disable sitemap generator by default; update CommentStreams extension; remove Favorites and MobileDetect extensions; add iputils-ping package
- 1.1.2 - July 12, 2022 - update MediaWiki version to 1.35.7; add default setting of $wgServer; add CookieWarning extension; update CommentStreams, Echo and EmbedVideo extensions; remove HeadScript extension; add poppler-utils package for PDF rendering
- 1.2.0 - October 2, 2022 - update MediaWiki version to 1.35.8; remove cfLoadExtension() and cfLoadSkin() functionality in favor of symlink-based approach; add displayWikiInfo.php script; make use of gateway.docker.internal to detect host address
- 1.2.1 - November 25, 2022 - add AArch64 support; update SimpleBatchUpload extension
- 1.2.2 - December 22, 2022 - Fix installation of EmailAuthorization extension; fix web installer to also install Boostrap extension if Chameleon skin gets installed; add MW_MAP_DOMAIN_TO_DOCKER_GATEWAY as an environment variable (set to true by default); remove patches made unnecessary by cfLoad... removal
- 1.3.0 - February 17, 2023 - update MediaWiki version to 1.39.0; update all extensions to a compatible version (in most cases, using the REL1_39 Git branch); add the extensions AbuseFilter, DeleteBatch, MediaUploader, Mermaid, SemanticDependencyUpdater, TemplateWizard, Title Icon, UserPageViewTracker, WatchAnalytics, WhosOnline; remove the extensions DiscussionTools, LocalisationUpdate; add the skin Vector 2022; add header warning to email-related special pages if $wgSMTP is not set
- 2.0.0 - December 11, 2023 - add wiki farm support; add maintenance-scripts/ directory; add automated symlinking of local versions of extensions and skins; add AWS, EditAccount, GTag, JWTAuth, TemplateSandbox, Semantic Tasks and Semantic Watchlist extensions
- 2.0.1 - April 14, 2024 - update MediaWiki version to 1.39.7; move extension installation settings from Dockerfile into extensions.yaml; rename run-apache.sh to run-all.sh; remove WikiForum extension
- 3.0.0 - June 23, 2025 - move most functionality into CanastaBase repository (which currently uses MediaWiki 1.43), leaving only extension- and skin-specific code; place all extension and skin installation settings into a single file, contents.yaml, which in turn inherits from "Recommended Revisions" page; add the DiscussionTools, InlineComments, LoginNotify, OAuth, Page Schemas, QuickInstantCommons and Paragraph-based Edit Conflict Interface ("TwoColConflict") extensions; remove the RenameUser, Semantic Breadcrumb Links, Semantic Forms Select, Semantic Tasks and TinyMCE extensions
- 3.0.1 - June 30, 2025 - update to CanastaBase 1.0.1, which uses MediaWiki 1.43.2
- 3.0.2 - July 1, 2025 - update to CanastaBase 1.0.2, which uses MediaWiki 1.43.3
