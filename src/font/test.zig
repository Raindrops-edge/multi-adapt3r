//! Fonts that can be embedded with Ghostty. Note they are only actually
//! embedded in the binary if they are referenced by the code, so fonts
//! used for tests will not result in the final binary being larger.
//!
//! Be careful to ensure that any fonts you embed are licensed for
//! redistribution and include their license as necessary.

/// Fonts with general properties
pub const fontRegular = @embedFile("res/Inconsolata-Regular.ttf");
pub const fontBold = @embedFile("res/Inconsolata-Bold.ttf");
pub const fontEmoji = @embedFile("res/NotoColorEmoji.ttf");
pub const fontEmojiText = @embedFile("res/NotoEmoji-Regular.ttf");
pub const fontVariable = @embedFile("res/Lilex-VF.ttf");

/// Font with nerd fonts embedded.
pub const fontNerdFont = @embedFile("res/JetBrainsMonoNerdFont-Regular.ttf");

/// Specific font families below:
pub const fontCodeNewRoman = @embedFile("res/CodeNewRoman-Regular.otf");
pub const fontGeistMono = @embedFile("res/GeistMono-Regular.ttf");
pub const fontJetBrainsMono = @embedFile("res/JetBrainsMonoNoNF-Regular.ttf");
pub const fontJuliaMono = @embedFile("res/JuliaMono-Regular.ttf");

/// Cozette is a unique font because it embeds some emoji characters
/// but has a text presentation.
pub const fontCozette = @embedFile("res/CozetteVector.ttf");

/// Monaspace has weird ligature behaviors we want to test in our shapers
/// so we embed it here.
pub const fontMonaspaceNeon = @embedFile("res/MonaspaceNeon-Regular.otf");
