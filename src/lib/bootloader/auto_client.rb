require "installation/auto_client"

module Bootloader
  # Autoyast client for bootloader
  class AutoClient < ::Installation::AutoClient
    def initialize
      Yast.import "UI"

      Yast.import "Bootloader"
      Yast.import "BootCommon"
      Yast.import "BootStorage"
      Yast.import "Initrd"
      Yast.import "Progress"
      Yast.import "Mode"

      Yast.include self, "bootloader/routines/autoinstall.rb"
      Yast.include self, "bootloader/routines/wizards.rb"
    end

    def run
      progress_orig = Yast::Progress.set(false)
      ret = super
      Yast::Progress.set(progress_orig)

      ret
    end

    def import(data)
      data = AI2Export(data)
      if data
        ret = Yast::Bootloader.Import(data)
        # moved here from inst_autosetup*
        if Yast::Stage.initial
          Yast::BootStorage.DetectDisks
          Yast::Bootloader.Propose
        end
      else
        log.error "Failed to convert autoyast profile to standard form"
        ret = false
      end

      ret
    end

    def summary
      formatted_summary = Yast::Bootloader.Summary.map { |l| "<LI>#{l}</LI>" }

      "<UL>" + formatted_summary.join("\n") + "</UL>"
    end

    def modified?
      BootCommon.changed
    end

    def modified
      BootCommon.changed = true
    end

    def reset
      Bootloader.Reset
    end

    def change
      BootloaderAutoSequence()
    end

    # Return configuration data
    #
    # Some of the sections are useless as they're ignored during import.
    # (for example, entries are generated by Grub2 itself).
    #
    # More details can be found in the original pull request at
    # https://github.com/yast/yast-bootloader/pull/272
    #
    # return map or list
    def export
      Export2AI(Yast::Bootloader.Export)
    end

    def write
      Yast::Bootloader.Write
    end

    def read
      Yast::Initrd.Read
      Yast::Bootloader.Read
    end
  end
end
