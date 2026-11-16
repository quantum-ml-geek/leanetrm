using System.Globalization;
using System.Text.Json;
using OpenEtrm.MarketData;

namespace OpenEtrm.Api;

public static partial class StructuredPowerPreview
{
    // Count dimensions may already have a different catalog code. The exact
    // resource-right unit supplies the economic meaning; dimensional exponents
    // prove that its normalization is a count without implying any certificate.
    internal static bool CompleteRightDimension(PreviewData data,string dimensionCode)
    {
        var row=Reference(data,"dimensions",dimensionCode);
        foreach(var field in new[]{"mass_power","length_power","time_power","temperature_power","amount_power","current_power","luminous_power"})
        {
            if(!row.TryGetProperty(field,out var value))return false;
            var integer=value.ValueKind==JsonValueKind.Number&&value.TryGetInt32(out var number)?number:
                value.ValueKind==JsonValueKind.String&&int.TryParse(value.GetString(),NumberStyles.Integer,CultureInfo.InvariantCulture,out number)?number:(int?)null;
            if(integer!=0)return false;
        }
        return true;
    }
}
