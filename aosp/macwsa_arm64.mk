$(call inherit-product, device/generic/goldfish/64bitonly/product/sdk_phone64_arm64.mk)

PRODUCT_NAME := macwsa_arm64
PRODUCT_DEVICE := emu64a
PRODUCT_BRAND := Android
PRODUCT_MODEL := MacWSA PoC Emulator
PRODUCT_MANUFACTURER := OpenAI

PRODUCT_PACKAGES += MacWsaAgent

PRODUCT_SOONG_NAMESPACES += vendor/macwsa
