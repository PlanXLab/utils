# Theme_20260930 for tOS
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'
  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  # ------------------------------------------------------------------
  # CPU Temperature
  # ------------------------------------------------------------------
  function prompt_sys_temp() {
    local temp
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
      temp=$(</sys/class/thermal/thermal_zone0/temp)
      p10k segment -f 232 -b 173 -i '' -t "$((temp/1000))°C"
    fi
  }

  # ------------------------------------------------------------------
  # Left & Right Prompt Elements Setup
  # ------------------------------------------------------------------
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    os_icon                 
    context                 
    dir                     
    vcs                     
    newline                 
    prompt_char             
  )

  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  
    command_execution_time  
    background_jobs         
    sys_temp                
    cpu_usage               
    ram                     
    time                    
    newline
  )

  typeset -g POWERLEVEL9K_MODE=nerdfont-v3
  
  typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=true 
  
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true

  # ------------------------------------------------------------------
  # Frame 
  # ------------------------------------------------------------------
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX='%242F╭─'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX='%242F├─'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX='%242F╰─'
  
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX='%242F─╮'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX='%242F─┤'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX='%242F─╯'

  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR='·'
  if [[ $POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR != ' ' ]]; then
    typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=237
  fi

  # ------------------------------------------------------------------
  # Separators 
  # ------------------------------------------------------------------
  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR='\uE0BC'
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR='\uE0BA'
  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR='\uE0BB'
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR='\uE0B9'
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL='\uE0BC'
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL='\uE0BA'
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=''

  # ------------------------------------------------------------------
  # Left Side Colors
  # ------------------------------------------------------------------
  
  # OS Icon: Muted Blue (109)
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=232
  typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND=109

  # Context
  typeset -g POWERLEVEL9K_CONTEXT_DEFAULT_FOREGROUND=250
  typeset -g POWERLEVEL9K_CONTEXT_DEFAULT_BACKGROUND=238
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=253
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_BACKGROUND=131
  typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_VISUAL_IDENTIFIER_EXPANSION='󰒋'
  typeset -g DEFAULT_USER=''

  # ------------------------------------------------------------------
  # Prompt
  # ------------------------------------------------------------------
  typeset -g POWERLEVEL9K_PROMPT_CHAR_BACKGROUND=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=109
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=131
  
  typeset -g POWERLEVEL9K_PROMPT_CHAR_VISUAL_IDENTIFIER_EXPANSION=''
  
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_{LEFT,RIGHT}_WHITESPACE=''
  
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='⚡'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='󰞷'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='󰊄'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true

  # Directory: Slate Blue (67)
  typeset -g POWERLEVEL9K_DIR_BACKGROUND=67
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=253
  typeset -g POWERLEVEL9K_DIR_VISUAL_IDENTIFIER_EXPANSION='󰉋'
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=250
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=255
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=1

  # Git VCS: Sage Green (108) / Soft Gold (179)
  typeset -g POWERLEVEL9K_VCS_CLEAN_BACKGROUND=108
  typeset -g POWERLEVEL9K_VCS_MODIFIED_BACKGROUND=179
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND=108
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_BACKGROUND=131

  function my_git_formatter() {
    emulate -L zsh
    if [[ -n $P9K_CONTENT ]]; then
      typeset -g my_git_format=$P9K_CONTENT
      return
    fi
    local       meta='%232F'
    local      clean='%232F'
    local   modified='%232F'
    local  untracked='%232F'
    local conflicted='%253F'
    local res
    
    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
      local branch=${(V)VCS_STATUS_LOCAL_BRANCH}
      (( $#branch > 32 )) && branch[13,-13]="…"
      res+="${clean}󰘬 ${branch//\%/%%}"
    fi

    if (( VCS_STATUS_COMMITS_AHEAD || VCS_STATUS_COMMITS_BEHIND )); then
      (( VCS_STATUS_COMMITS_BEHIND )) && res+=" ${clean}󰐙 ${VCS_STATUS_COMMITS_BEHIND}"
      (( VCS_STATUS_COMMITS_AHEAD  )) && res+=" ${clean}󰐕 ${VCS_STATUS_COMMITS_AHEAD}"
    fi
    
    (( VCS_STATUS_STASHES        )) && res+=" ${clean}󰏗 ${VCS_STATUS_STASHES}"
    (( VCS_STATUS_NUM_CONFLICTED )) && res+=" ${conflicted}󰚌 ${VCS_STATUS_NUM_CONFLICTED}"
    (( VCS_STATUS_NUM_STAGED     )) && res+=" ${modified}󰐖 ${VCS_STATUS_NUM_STAGED}"
    (( VCS_STATUS_NUM_UNSTAGED   )) && res+=" ${modified}󰏫 ${VCS_STATUS_NUM_UNSTAGED}"
    (( VCS_STATUS_NUM_UNTRACKED  )) && res+=" ${untracked}󰡯 ${VCS_STATUS_NUM_UNTRACKED}"
    
    typeset -g my_git_format=$res
  }
  functions -M my_git_formatter 2>/dev/null
  typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((my_git_formatter()))+${my_git_format}}'

  # ------------------------------------------------------------------
  # Right Side Colors
  # ------------------------------------------------------------------
  
  # Command Run-time
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=232
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND=143
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_VISUAL_IDENTIFIER_EXPANSION='󱎫'

  # CPU Usage
  typeset -g POWERLEVEL9K_CPU_USAGE_FOREGROUND=232
  typeset -g POWERLEVEL9K_CPU_USAGE_BACKGROUND=108
  typeset -g POWERLEVEL9K_CPU_USAGE_VISUAL_IDENTIFIER_EXPANSION='󰻠'

  # RAM Usage
  typeset -g POWERLEVEL9K_RAM_FOREGROUND=253
  typeset -g POWERLEVEL9K_RAM_BACKGROUND=67
  typeset -g POWERLEVEL9K_RAM_VISUAL_IDENTIFIER_EXPANSION='󰍛'

  # Current Time
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=232
  typeset -g POWERLEVEL9K_TIME_BACKGROUND=109
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'
  typeset -g POWERLEVEL9K_TIME_VISUAL_IDENTIFIER_EXPANSION='󰥔'

  # Status
  typeset -g POWERLEVEL9K_STATUS_OK_VISUAL_IDENTIFIER_EXPANSION='󰄬'
  typeset -g POWERLEVEL9K_STATUS_OK_FOREGROUND=108
  typeset -g POWERLEVEL9K_STATUS_OK_BACKGROUND=237
  typeset -g POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION='󰚌'
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=253
  typeset -g POWERLEVEL9K_STATUS_ERROR_BACKGROUND=131

  # Frameworks & UI Settings
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true
  (( ! $+functions[p10k] )) || p10k reload
}

typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}
(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
