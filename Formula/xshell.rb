class Xshell < Formula
  desc "Secure remote shell host and CLI client"
  homepage "https://github.com/xshelld/xshell"
  url "https://pkg.xshell.online/brew/xshell-1.0.17.tar.gz"
  version "1.0.17"
  sha256 "845fbdea50bfa0d08d24eda1dc431357daf27373b88f66ead4d48cb32ce81c64"
  license "GPL-3.0-or-later"
  revision 2

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "openssl@3"

  resource "libdatachannel" do
    url "https://pkg.xshell.online/brew/libdatachannel-28b2e730f4c7.tar.gz"
    sha256 "4b691a974b1265a5e55b0b0667fd366ea2542fdcd1ad4ea38243aedfa7f49039"
  end

  def install
    vendor_prefix = buildpath/"vendor/libdatachannel"

    resource("libdatachannel").stage do
      system "cmake", "-S", ".", "-B", "build",
             "-DCMAKE_BUILD_TYPE=Release",
             "-DCMAKE_INSTALL_PREFIX=#{vendor_prefix}",
             "-DNO_MEDIA=ON",
             "-DNO_WEBSOCKET=ON",
             "-DOPENSSL_ROOT_DIR=#{Formula["openssl@3"].opt_prefix}"
      system "cmake", "--build", "build"
      system "cmake", "--install", "build"
    end

    vendor_include = vendor_prefix/"include"
    vendor_libdir = (vendor_prefix/"lib64").directory? ? vendor_prefix/"lib64" : vendor_prefix/"lib"
    openssl_prefix = Formula["openssl@3"].opt_prefix

    common_rtc_block = <<~EOS
      ifneq ($(wildcard /usr/local/include/rtc/rtc.h),)
          CFLAGS += -I/usr/local/include
          LDFLAGS += -L/usr/local/lib -Wl,-rpath,/usr/local/lib
      else ifneq ($(wildcard /opt/homebrew/include/rtc/rtc.h),)
          CFLAGS += -I/opt/homebrew/include
          LDFLAGS += -L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib
      endif
    EOS

    host_client_rtc_block = <<~EOS
      ifneq ($(wildcard /usr/local/include/rtc/rtc.h),)
          CFLAGS += -I/usr/local/include
          LDFLAGS += -L/usr/local/lib -Wl,-rpath,/usr/local/lib
      else ifneq ($(wildcard /opt/homebrew/include/rtc/rtc.h),)
          CFLAGS += -I/opt/homebrew/include
          LDFLAGS += -L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib
      endif
    EOS

    inreplace "src/common/Makefile",
              "OPENSSL_PREFIX := $(shell brew --prefix openssl 2>/dev/null)",
              "OPENSSL_PREFIX := #{openssl_prefix}"
    inreplace "src/common/Makefile",
              common_rtc_block,
              "CFLAGS += -I#{vendor_include}\n"

    ["src/host/Makefile", "src/client/Makefile"].each do |path|
      inreplace path,
                "LDFLAGS = -L../../xutils/build/ -L/usr/local/lib64/ -Wl,-rpath,/usr/local/lib64",
                "LDFLAGS = -L../../xutils/build/ -L#{vendor_libdir} -Wl,-rpath,#{libexec}/lib"
      inreplace path,
                "OPENSSL_PREFIX := $(shell brew --prefix openssl 2>/dev/null)",
                "OPENSSL_PREFIX := #{openssl_prefix}"
      inreplace path,
                host_client_rtc_block,
                "CFLAGS += -I#{vendor_include}\n"
    end

    system "bash", "./xutils/build.sh"
    system "make", "-C", "src/common"
    system "make", "-C", "src/host"
    system "make", "-C", "src/client"

    bin.install "obj/host/xshell", "obj/client/xshcli"
    (libexec/"lib").install Dir["#{vendor_libdir}/libdatachannel*"]
    doc.install "README.md", "LICENSE", "pkg/CHANGELOG.md"
  end

  service do
    run [opt_bin/"xshell"]
    keep_alive true
    working_dir Dir.home
    log_path var/"log/xshell.log"
    error_log_path var/"log/xshell.log"
  end

  def caveats
    <<~EOS
      Generate the host config once before starting the service:
        #{opt_bin}/xshell -i

      Then start the launchd service:
        brew services start xshell
    EOS
  end

  test do
    assert_match "Usage", shell_output("#{bin}/xshcli -h 2>&1")
  end
end
