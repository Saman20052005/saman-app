import 'package:flutter/material.dart';

/// Scoped localization dictionary for the Saman Shop module.
///
/// Ensures all UI labels cleanly support both Vietnamese (`vi`) and English (`en`),
/// reacting immediately to locale switches without requiring app-wide refactoring.
class ShopTranslations {
  ShopTranslations._();

  static const Map<String, Map<String, String>> _localizedValues = {
    'vi': {
      'shop_title': 'Saman Shop',
      'search_placeholder': 'Tìm sản phẩm',
      'hero_title': 'Đồ tốt cho\nnhịp tập của bạn.',
      'hero_subtitle': 'Tuyển chọn tinh giản từ dụng cụ đến dinh dưỡng.',
      'hero_explore': 'Khám phá',
      'category_all': 'Tất cả',
      'category_training': 'Tập luyện',
      'category_recovery': 'Phục hồi',
      'category_nutrition': 'Bữa ăn',
      'curated_header': 'TUYỂN CHỌN',
      'featured_products_count': '{count} sản phẩm nổi bật',
      'products_count': '{count} sản phẩm',
      'collection_section_label': 'Bộ sưu tập',
      'collection_action': 'Xem',
      'demo_badge': 'Dữ liệu minh họa',
      'price_approx_format': '~{price} đ',
      'view_price_on_shopee': 'Xem giá trên Shopee',
      'save_product': 'Lưu sản phẩm',
      'saved_title': 'Mục đã lưu',
      'saved_items_count': '{count} mục đã lưu',
      'empty_catalog_title': 'Chưa có sản phẩm nào',
      'empty_catalog_subtitle':
          'Catalog sản phẩm tuyển chọn đang được cập nhật.',
      'no_results_title': 'Không tìm thấy sản phẩm',
      'no_results_subtitle':
          'Thử tìm kiếm với từ khóa hoặc bộ lọc danh mục khác.',
      'reset_filters': 'Đặt lại bộ lọc',
      'first_page_error_title': 'Không thể tải danh mục sản phẩm',
      'first_page_error_subtitle': 'Vui lòng kiểm tra kết nối mạng và thử lại.',
      'retry': 'Thử lại',
      'load_more_error': 'Không thể tải thêm sản phẩm. Chạm để thử lại.',
      'active_collection_filter': 'Bộ sưu tập: {title}',
      'clear_filter': 'Xóa lọc',

      // Product Detail
      'curation_why_saman': 'Vì sao Saman chọn',
      'specifications_header': 'Thông số & Quy cách',
      'seller_prefix': 'Cung cấp bởi {seller}',
      'price_updated_at': 'Giá tham khảo cập nhật: {date}',
      'cta_view_on_shopee_demo': 'Xem trên Shopee (Minh họa)',
      'cta_view_on_shopee': 'Xem trên Shopee',
      'cta_unavailable': 'Tạm hết hàng',
      'cta_discontinued': 'Ngừng phân phối',
      'product_not_found_title': 'Sản phẩm không tồn tại',
      'product_not_found_subtitle':
          'Sản phẩm này có thể đã bị gỡ hoặc đường dẫn không đúng.',
      'back_to_catalog': 'Quay lại danh mục',
      'error_loading_product': 'Không thể tải thông tin sản phẩm',
      'unsave_product': 'Bỏ lưu',

      // Saved Screen
      'saved_empty_title': 'Chưa có sản phẩm nào được lưu',
      'saved_empty_subtitle':
          'Chạm vào biểu tượng bookmark trên sản phẩm để lưu lại xem sau.',
      'explore_catalog_action': 'Khám phá danh mục',
      'missing_product_in_catalog': 'Sản phẩm không còn trong danh mục',
      'missing_product_id': 'Mã ID: {id}',

      // Commercial Disclosures (CP-SHOP-08)
      'disclosure_affiliate':
          'Saman có thể nhận hoa hồng từ các giao dịch đủ điều kiện qua liên kết này.',
      'disclosure_external_redirect':
          'Tiếp tục mua hàng trên Shopee.',

      // Demo Explanation Bottom Sheet
      'demo_sheet_title': 'Sản phẩm minh họa',
      'demo_sheet_description':
          'Sản phẩm minh họa, chưa có liên kết mua thực tế.',
      'demo_sheet_close': 'Đã hiểu',

      // Launcher notifications
      'launcher_error_title': 'Không thể kết nối',
      'launcher_error_message':
          'Không thể mở liên kết sản phẩm. Vui lòng thử lại sau.',
      'launcher_retry': 'Thử lại',
    },
    'en': {
      'shop_title': 'Saman Shop',
      'search_placeholder': 'Search products',
      'hero_title': 'Good gear for\nyour workout rhythm.',
      'hero_subtitle': 'Curated essentials from gear to nutrition.',
      'hero_explore': 'Explore',
      'category_all': 'All',
      'category_training': 'Training',
      'category_recovery': 'Recovery',
      'category_nutrition': 'Meal Prep',
      'curated_header': 'CURATED',
      'featured_products_count': '{count} featured items',
      'products_count': '{count} items',
      'collection_section_label': 'Collection',
      'collection_action': 'View',
      'demo_badge': 'Demo Data',
      'price_approx_format': '~{price} VND',
      'view_price_on_shopee': 'View price on Shopee',
      'save_product': 'Save product',
      'saved_title': 'Saved Items',
      'saved_items_count': '{count} saved items',
      'empty_catalog_title': 'No products available',
      'empty_catalog_subtitle':
          'The curated catalog is currently being updated.',
      'no_results_title': 'No products found',
      'no_results_subtitle':
          'Try searching with different keywords or category filters.',
      'reset_filters': 'Reset filters',
      'first_page_error_title': 'Unable to load catalog',
      'first_page_error_subtitle': 'Please check your connection and try again.',
      'retry': 'Retry',
      'load_more_error': 'Failed to load more items. Tap to retry.',
      'active_collection_filter': 'Collection: {title}',
      'clear_filter': 'Clear',

      // Product Detail
      'curation_why_saman': 'Why Saman picked this',
      'specifications_header': 'Specifications & Details',
      'seller_prefix': 'Provided by {seller}',
      'price_updated_at': 'Reference price updated: {date}',
      'cta_view_on_shopee_demo': 'View on Shopee (Demo)',
      'cta_view_on_shopee': 'View on Shopee',
      'cta_unavailable': 'Out of stock',
      'cta_discontinued': 'Discontinued',
      'product_not_found_title': 'Product not found',
      'product_not_found_subtitle':
          'This product may have been unlisted or the link is invalid.',
      'back_to_catalog': 'Back to catalog',
      'error_loading_product': 'Unable to load product details',
      'unsave_product': 'Unsave',

      // Saved Screen
      'saved_empty_title': 'No saved products yet',
      'saved_empty_subtitle':
          'Tap the bookmark icon on any item to save it for later.',
      'explore_catalog_action': 'Explore catalog',
      'missing_product_in_catalog': 'Product no longer in catalog',
      'missing_product_id': 'ID: {id}',

      // Commercial Disclosures (CP-SHOP-08)
      'disclosure_affiliate':
          'Saman may earn a commission on qualifying purchases via this link.',
      'disclosure_external_redirect':
          'Continue shopping on Shopee.',

      // Demo Explanation Bottom Sheet
      'demo_sheet_title': 'Curated Demo Item',
      'demo_sheet_description':
          'Curated sample item, no external purchase link yet.',
      'demo_sheet_close': 'Understood',

      // Launcher notifications
      'launcher_error_title': 'Unable to connect',
      'launcher_error_message':
          'Could not open product link. Please try again later.',
      'launcher_retry': 'Retry',
    },
  };

  /// Returns translated string by key for given locale, fallback to 'vi', then 'en'.
  static String text(String key, Locale locale) {
    final lang = locale.languageCode.toLowerCase();
    final dict = _localizedValues[lang] ?? _localizedValues['vi']!;
    return dict[key] ?? _localizedValues['en']?[key] ?? key;
  }

  /// Convenience helper to read translation using BuildContext.
  static String of(BuildContext context, String key) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('vi');
    return text(key, locale);
  }
}
