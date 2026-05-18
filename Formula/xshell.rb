class Xshell < Formula
  desc "Secure remote shell host and CLI client"
  homepage "https://github.com/xshelld/xshell"
  url "https://pkg.xshell.online/brew/xshell-1.0.17.tar.gz"
  version "1.0.17"
  sha256 "6b64cd5844269341c30c800d66e39edfc5d713fe8bfaad9b665a7cc3f195c94e"
  license "GPL-3.0-or-later"
  revision 6

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "openssl@3"

  resource "libdatachannel" do
    url "https://pkg.xshell.online/brew/libdatachannel-28b2e730f4c7.tar.gz"
    sha256 "b058f73c0f6530af735ecd75c2107396ca9a55f23d0c790a89ec7b21744ad39f"
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
    inreplace "src/common/logger.c",
              '#define XSHELL_LOG_PATH_DEFAULT "/var/log/xshell"',
              "#define XSHELL_LOG_PATH_DEFAULT \"#{var}/log/xshell\""

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

  def post_install
    (var/"log/xshell").mkpath
  end

  service do
    run [opt_bin/"xshell"]
    keep_alive true
    working_dir Dir.home
    log_path var/"log/xshell/xshell.log"
    error_log_path var/"log/xshell/xshell.log"
  end

  def caveats
    <<~EOS
      Log in in the browser to enroll your fisrs device:
        https://xshell.online/login

      Then start the launchd service:
        brew services start xshell
    EOS
  end

  test do
    assert_match "Usage", shell_output("#{bin}/xshcli -h 2>&1")
  end
end
