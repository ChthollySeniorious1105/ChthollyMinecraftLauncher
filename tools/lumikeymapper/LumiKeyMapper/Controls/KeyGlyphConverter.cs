using System.Globalization;
using System.Windows.Data;
using LumiKeyMapper.Core;

namespace LumiKeyMapper.Controls;

/// <summary>Maps an <see cref="InputKey"/> to its Segoe Fluent Icons device glyph.</summary>
public sealed class KeyGlyphConverter : IValueConverter
{
    public static KeyGlyphConverter Instance { get; } = new();
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value is InputKey key ? InputPicker.Glyph(key) : "";
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
