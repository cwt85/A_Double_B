namespace ADoubleB.ViewModel;

public class UserHistory 
{
	public int UserNumber { get; set; }
	public int ACount { get; set; }
	public int BCount { get; set; }
	public int TryCount { get; set; }
	public string Message => $"輸入數字：{UserNumber}，{ACount}A{BCount}B，共嘗試{TryCount}次";
}