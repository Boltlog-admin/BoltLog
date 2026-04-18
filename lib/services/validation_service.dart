import '../constants/app_constants.dart';

class ValidationService {
  // Email validation
  static String? validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'Email is required';
    }
    
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email.trim())) {
      return 'Please enter a valid email address';
    }
    
    return null;
  }

  // Phone number validation
  static String? validatePhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return 'Phone number is required';
    }
    
    // Remove spaces and special characters
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // Check if it's a valid Zimbabwe phone number format
    if (cleaned.startsWith('+263')) {
      if (cleaned.length != 13) {
        return 'Invalid phone number format';
      }
    } else if (cleaned.startsWith('0')) {
      if (cleaned.length != 10) {
        return 'Invalid phone number format';
      }
    } else {
      return 'Phone number must start with +263 or 0';
    }
    
    return null;
  }

  // Password validation
  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }
    
    if (password.length < AppConstants.minPasswordLength) {
      return 'Password must be at least ${AppConstants.minPasswordLength} characters';
    }
    
    return null;
  }

  // Name validation
  static String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Name is required';
    }
    
    if (name.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    
    if (name.length > AppConstants.maxNameLength) {
      return 'Name must be less than ${AppConstants.maxNameLength} characters';
    }
    
    return null;
  }

  // Required field validation
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  // Price validation
  static String? validatePrice(String? price) {
    if (price == null || price.trim().isEmpty) {
      return 'Price is required';
    }
    
    final priceValue = double.tryParse(price.trim());
    if (priceValue == null) {
      return 'Please enter a valid price';
    }
    
    if (priceValue <= 0) {
      return 'Price must be greater than 0';
    }
    
    return null;
  }

  // Sanitize input (remove HTML, escape special chars)
  static String sanitizeInput(String? input) {
    if (input == null) return '';
    
    // Remove HTML tags
    String sanitized = input.replaceAll(RegExp(r'<[^>]*>'), '');
    
    // Trim whitespace
    sanitized = sanitized.trim();
    
    // Limit length
    if (sanitized.length > AppConstants.maxDescriptionLength) {
      sanitized = sanitized.substring(0, AppConstants.maxDescriptionLength);
    }
    
    return sanitized;
  }

  // Validate image file
  static String? validateImageFile(dynamic file, {String? fieldName}) {
    if (file == null) {
      return '${fieldName ?? 'Image'} is required';
    }
    return null;
  }
}
