# Evaluate the actual Brewfile DSL when macOS supplies Ruby; Linux runtime tests
# use native-command fixtures and do not require Ruby or Homebrew.
class BrewfileCapture
  attr_reader :formulae, :casks

  def initialize
    @formulae = []
    @casks = []
  end

  def brew(name)
    @formulae << name
  end

  def cask(name)
    @casks << name
  end
end

expected = {
  'common' => [
    %w[go python uv awscli kind kubernetes-cli opentofu podman podman-compose
       protobuf zsh-autocomplete zsh-autosuggestions zsh-syntax-highlighting
       zsh-you-should-use starship bat btop dust eza fzf git-delta jq lazygit
       ripgrep tree yazi zoxide rtk],
    %w[bruno podman-desktop ghostty github jetbrains-toolbox lapce
       font-jetbrains-mono-nerd-font]
  ],
  'home' => [[], %w[brave-browser google-chrome rectangle]],
  'work' => [
    %w[groovy jenv node nodenv prettier tsc vault yq],
    %w[claude-code corretto@21 pgadmin4]
  ]
}

[nil, 'desktop', 'headless'].each do |mode|
  mode.nil? ? ENV.delete('DOTFILES_GUI') : ENV['DOTFILES_GUI'] = mode
  expected.each do |profile, (formulae, desktop_casks)|
    file = File.join(ARGV.fetch(0), "Brewfile.#{profile}")
    capture = BrewfileCapture.new
    capture.instance_eval(File.read(file), file)
    casks = if mode == 'headless'
      profile == 'work' ? %w[claude-code corretto@21] : []
    else
      desktop_casks
    end
    raise "#{profile}/#{mode}: formulae changed" unless capture.formulae == formulae
    raise "#{profile}/#{mode}: wrong casks" unless capture.casks == casks
  end
end