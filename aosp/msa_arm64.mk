$(call inherit-product, device/generic/goldfish/64bitonly/product/sdk_phone64_arm64.mk)

PRODUCT_NAME := msa_arm64
PRODUCT_DEVICE := emu64a
PRODUCT_BRAND := Android
PRODUCT_MODEL := MSA Emulator
PRODUCT_MANUFACTURER := MSA

PRODUCT_PACKAGES += MsaAgent

PRODUCT_SOONG_NAMESPACES += vendor/msa
