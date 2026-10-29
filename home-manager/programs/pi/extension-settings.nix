{
  "pi-cc-extensions.json" = {
    mode = "on";
    excludeRenderers = [ ];
    diffViewMode = "auto";
    diffIndicatorMode = "bars";
    diffSplitMinWidth = 120;
    editDiffCollapsedLines = 24;
    writeDiffCollapsedLines = 0;
    diffWordWrap = true;
    expandedPreviewMaxLines = 40;
    expandedInputMaxLines = 5;
    expandedOutputMaxLines = 10;
    inputClip = 100;
    useSummaryTitlesAsThinkingTitle = true;
    previewLines = 3;
    animationIntervalMs = 90;
    dimThinkingText = false;
    showStartupHeader = true;
    scrollStepLines = 3;
    enableSessionReference = true;
    enableSubagentAutocomplete = true;
    enableContextCommand = true;
    enableAgentSummary = true;
    enableWorkingMessage = true;
    enableAliases = true;
    enableCustomFooter = true;
    footerNerdIcons = true;
    footerHiddenKeys = [ ];
    footerLine1Keys = [ "pi-usage" ];
    footerLine2Keys = [ ];
    footerLine3Keys = [ ];
  };
  "zentui.json" = {
    components = {
      editor = {
        enabled = true;
        style = "opencode-copy-friendly";
        colorSource = "theme";
        borderColorMode = "static";
        modelLabel = "id";
        viewportIndicators = true;
        styles = {
          opencode = {
            metadataFormat = "$model  $provider(  $thinking)";
          };
          opencode-copy-friendly = {
            metadataFormat = "$model  $provider(  $thinking)";
          };
          minimalist = {
            pathDisplay = "compact";
            contextFormat = "percent";
            contextGauge = false;
            showSessionName = true;
            showTimer = true;
            showCost = true;
            showGit = true;
            contextThresholds = {
              warning = 70;
              error = 90;
            };
          };
        };
      };
      userMessages = {
        enabled = true;
        style = "framed";
        colorSource = "theme";
        styles = {
          framed = { };
          framed-copy-friendly = { };
          compact = { };
          labeled = { };
        };
      };
      selectorBorders = {
        enabled = true;
        style = "zentui";
        colorSource = "terminal";
      };
      footer = {
        style = "starship";
        colorSource = "terminal";
        modelLabel = "id";
        styles = {
          starship = {
            format = "";
            responsive = true;
            compactFormat = "$cwd$wrap(in $session_name)$wrap(on $git_branch) $git_status$wrap$context$wrap_sep$tokens";
            compactMaxLines = 2;
            separator = "pipe";
            contextStyle = "text";
            contextThresholds = {
              warning = 70;
              error = 90;
            };
            pathDisplay = {
              mode = "full";
              depth = 0;
            };
            segments = {
              cwd = true;
              sessionName = true;
              gitBranch = true;
              gitStatus = true;
              gitCounts = true;
              gitCommit = true;
              gitMetrics = true;
              runtime = true;
              modelInfo = false;
              context = true;
              tokens = true;
              cost = false;
              sessionDuration = false;
              username = false;
              time = false;
              os = false;
              packageVersion = false;
            };
            gitBranch = {
              maxLength = "full";
            };
            gitCommit = {
              hashLength = 7;
              onlyDetached = true;
              showTag = true;
            };
            gitMetrics = {
              onlyNonzero = true;
              ignoreSubmodules = false;
            };
            extensionStatuses = {
              defaultPlacement = "right";
              placements = {
                pi-permission-system = "left";
                background-tasks = "middle";
              };
              colorModes = {
                pi-permission-system = "zentui";
                pi-automode = "zentui";
                background-tasks = "zentui";
              };
            };
          };
        };
      };
      workingLine = {
        enabled = false;
        turnSummary = true;
        spinner = "star-bloom";
        spinnerIntervalMs = 100;
        animateSpinnerColor = false;
        textIntervalMs = 60;
        textAnimation = "classic";
        colorSource = "theme";
        messages = {
          custom = true;
          values = [
            "Sautéing…"
            "Cooking…"
            "Ionizing…"
            "Zigzagging…"
            "Razzle-dazzling…"
            "Photosynthesizing…"
            "Nucleating…"
            "Brewing…"
            "Combobulating…"
            "Boogieing…"
            "Befuddling…"
            "Alchemizing…"
            "Conjuring…"
            "Baking…"
            "Simmering…"
            "Blanching…"
          ];
        };
        segments = {
          tool = true;
          elapsed = true;
          thought = true;
          tokens = true;
        };
      };
    };
    icons = {
      mode = "auto";
    };
  };
}
