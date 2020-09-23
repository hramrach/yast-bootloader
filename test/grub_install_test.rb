#! /usr/bin/env rspec --format doc
# frozen_string_literal: true

require_relative "./test_helper"

require "bootloader/grub_install"

describe Bootloader::GrubInstall do
  describe "#execute" do
    def stub_arch(arch)
      allow(Yast::Arch).to receive(:architecture).and_return(arch)
    end

    def stub_efivars(removable: false)
      efivardirs = if removable
        []
      else
        ["Boot0000-8be4df61-93ca-11d2-aa0d-00e098032b8c",
         "BootCurrent-8be4df61-93ca-11d2-aa0d-00e098032b8c",
         "BootOrder-8be4df61-93ca-11d2-aa0d-00e098032b8c"]
      end

      allow(Dir).to receive(:glob).and_return(efivardirs)
    end

    def expect_grub2_install(target, device: nil, removable: false, no_nvram: false)
      params = [/grub2-install/, "--target=#{target}", "--force", "--skip-fs-probe"]
      params << "--removable" if removable
      params << "--no-nvram" if no_nvram
      params << device if device

      if device
        expect(Yast::Execute).to receive(:on_target!)
          .with(params)
      else
        expect(Yast::Execute).to receive(:on_target)
          .with(params)
      end
    end

    before do
      allow(::File).to receive(:directory?).and_return(false)
    end

    context "initialized with efi: true" do
      subject { Bootloader::GrubInstall.new(efi: true) }

      it "runs shim-install instead of grub2-install if secure_boot: true passed for non-arm" do
        stub_arch("x86_64")
        stub_efivars
        expect(Yast::Execute).to receive(:on_target)
          .with([/shim-install/, "--config-file=/boot/grub2/grub.cfg"])

        subject.execute(secure_boot: true)
      end

      it "runs grub2-install with --suse-force-signed on aarch64 with secure boot" do
        stub_arch("aarch64")
        stub_efivars(removable: true)

        expect(Yast::Execute).to receive(:on_target)
          .with([/grub2-install/, anything, "--suse-force-signed", anything, anything, anything, anything])

        subject.execute(secure_boot: true)
      end

      it "runs with target i386-efi on i386" do
        stub_arch("i386")
        stub_efivars
        expect_grub2_install("i386-efi")

        subject.execute
      end

      it "runs with target x86_64-efi on x86_64" do
        stub_arch("x86_64")
        stub_efivars
        expect_grub2_install("x86_64-efi")

        subject.execute
      end

      it "raise exception on ppc64" do
        stub_arch("ppc64")
        stub_efivars

        expect { subject.execute }.to raise_error(RuntimeError)
      end

      it "raise exception on s390" do
        stub_arch("s390_64")
        stub_efivars

        expect { subject.execute }.to raise_error(RuntimeError)
      end

      it "runs with target arm64-efi on aarch64" do
        stub_arch("aarch64")
        stub_efivars(removable: true)
        expect_grub2_install("arm64-efi", removable: true)

        subject.execute(devices: [])
      end

      it "runs twice as removable and non removable on aarch64 with efi vars (bsc#1167015)" do
        stub_arch("aarch64")
        stub_efivars(removable: false)
        expect_grub2_install("arm64-efi", removable: false)
        expect_grub2_install("arm64-efi", removable: true)

        subject.execute(devices: [])
      end

      it "raise exception for other architectures" do
        stub_arch("punks_not_dead")

        expect { subject.execute }.to raise_error(RuntimeError)
      end

      it "creates a removable grub2 install on non-nvram systems" do
        stub_arch("aarch64")
        stub_efivars(removable: true)
        expect_grub2_install("arm64-efi", removable: true)

        subject.execute
      end

      it "grub2 install asked to not update nvram" do
        stub_arch("aarch64")
        stub_efivars
        expect_grub2_install("arm64-efi", no_nvram: true)

        subject.execute(update_nvram: false)
      end

      it "passes suse-enable-tpm option when trusted boot is requested" do
        stub_arch("x86_64")
        stub_efivars

        expect(Yast::Execute).to receive(:on_target) do |arg|
          expect(arg).to include("--suse-enable-tpm")
        end

        subject.execute(trusted_boot: true)
      end
    end

    context "initialized with efi:false" do
      before do
        # no efi vars without efi
        stub_efivars(removable: true)
      end

      subject { Bootloader::GrubInstall.new(efi: false) }

      it "do not raise exception if secure_boot: true passed" do
        stub_arch("x86_64")
        expect { subject.execute(secure_boot: true) }.to_not raise_error
      end

      it "runs for each device passed in devices" do
        stub_arch("x86_64")
        expect_grub2_install("i386-pc", device: "/dev/sda")
        expect_grub2_install("i386-pc", device: "/dev/sdb")
        expect_grub2_install("i386-pc", device: "/dev/sdc")

        subject.execute(devices: ["/dev/sda", "/dev/sdb", "/dev/sdc"])
      end

      it "returns each device for which grub2-install failed" do
        stub_arch("x86_64")
        expect_grub2_install("i386-pc", device: "/dev/sdb")

        allow(Yast::Execute).to receive(:on_target!) do |arg|
          raise Cheetah::ExecutionFailed.new([], nil, nil, nil) if (arg & ["/dev/sda", "/dev/sdc"]).any?
        end

        expect(subject.execute(devices: ["/dev/sda", "/dev/sdb", "/dev/sdc"])).to contain_exactly("/dev/sda", "/dev/sdc")
      end

      it "opens a report if grub2-install failed for all devices" do
        stub_arch("x86_64")

        allow(Yast::Execute).to receive(:on_target!) do |_arg|
          raise Cheetah::ExecutionFailed.new([], nil, nil, nil)
        end

        expect(Yast::Report).to receive(:Error)

        subject.execute(devices: ["/dev/sda", "/dev/sdb", "/dev/sdc"])
      end

      it "runs with target i386-pc on i386" do
        stub_arch("i386")
        expect_grub2_install("i386-pc", device: "/dev/sda")

        subject.execute(devices: ["/dev/sda"])
      end

      it "runs with target i386-pc on x86_64" do
        stub_arch("x86_64")
        expect_grub2_install("i386-pc", device: "/dev/sda")

        subject.execute(devices: ["/dev/sda"])
      end

      it "runs with target powerpc-ieee1275 on ppc64" do
        stub_arch("ppc64")
        expect_grub2_install("powerpc-ieee1275", device: "/dev/sda")

        subject.execute(devices: ["/dev/sda"])
      end

      it "runs with target s390x-emu on s390" do
        stub_arch("s390_64")

        expect_grub2_install("s390x-emu")

        subject.execute(devices: [])
      end

      it "pass directory argument when trusted boot is requested" do
        stub_arch("x86_64")

        expect(Yast::Execute).to receive(:on_target!) do |arg|
          expect(arg).to include("--directory=/usr/lib/trustedgrub2/i386-pc")
        end

        subject.execute(devices: ["/dev/sda"], trusted_boot: true)
      end

      it "raise exception on aarch64" do
        stub_arch("aarch64")

        expect { subject.execute }.to raise_error(RuntimeError)
      end

      it "raise exception for other architectures" do
        stub_arch("punks_not_dead")

        expect { subject.execute }.to raise_error(RuntimeError)
      end

    end
  end
end
